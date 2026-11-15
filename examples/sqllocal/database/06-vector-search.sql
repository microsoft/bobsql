USE CaldovaRegionalCare;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE ai.usp_SearchTransferHistory
    @TransferNumber varchar(30),
    @Query nvarchar(max),
    @TopK int = 5
AS
BEGIN
    SET NOCOUNT ON;
    IF @TopK IS NULL OR @TopK < 1 OR @TopK > 20
        THROW 50045, 'TopK must be between 1 and 20.', 1;
    IF @Query IS NULL OR LEN(LTRIM(RTRIM(@Query))) = 0 OR DATALENGTH(@Query) > 8000
        THROW 50041, 'Search query must contain 1 to 4000 UTF-16 code units.', 1;
    DECLARE @PersonId bigint, @TransferStartedAt datetime2(3);
    SELECT @PersonId = e.PersonId, @TransferStartedAt = e.StartedAt
    FROM ops.Transfer AS t JOIN care.Encounter AS e ON e.EncounterId = t.EncounterId
    WHERE t.TransferNumber = @TransferNumber;
    IF @PersonId IS NULL
        THROW 50046, 'Unknown transfer number.', 1;
    IF EXISTS (
        SELECT 1 FROM care.HistoricalNote AS n
        LEFT JOIN ai.HistoricalNoteEmbedding AS e ON e.HistoricalNoteId = n.HistoricalNoteId
        WHERE n.PersonId = @PersonId AND n.RecordedAt < @TransferStartedAt
          AND (e.HistoricalNoteId IS NULL OR e.ContentHash <> HASHBYTES('SHA2_256', CONVERT(nvarchar(max), N'passage: ') + n.NoteText)
               OR e.ModelId <> 'nemotron-3-embed-1b-bf16'))
        THROW 50047, 'Historical embeddings are missing or stale; run the refresh procedure.', 1;
    IF NOT EXISTS (SELECT 1 FROM care.HistoricalNote
                   WHERE PersonId = @PersonId AND RecordedAt < @TransferStartedAt)
    BEGIN
        SELECT TOP (0) n.HistoricalNoteId, n.SourceCode, n.PersonId, n.RecordedAt,
            n.Title, n.AuthoredBy, n.NoteText, n.IsSynthetic, e.ModelId,
            CAST(NULL AS float) AS CosineDistance,
            CONVERT(varchar(18), CONVERT(binary(8), n.NoteVersion), 1) AS SourceVersion
        FROM care.HistoricalNote AS n
        JOIN ai.HistoricalNoteEmbedding AS e ON e.HistoricalNoteId = n.HistoricalNoteId;
        RETURN;
    END;
    -- This preview post-filters ANN results. Overfetch this small demo corpus
    -- before enforcing patient/date/freshness predicates and the requested TopK.
    DECLARE @Candidates int = (SELECT COUNT(*) FROM ai.HistoricalNoteEmbedding);
    DECLARE @Vector VECTOR(2048, float16), @Input nvarchar(max) = N'query: ' + @Query;
    SET @Vector = CAST(
        AI_GENERATE_EMBEDDINGS(@Input USE MODEL CaldovaHistoryEmbeddingModel)
        AS VECTOR(2048, float16));
    IF @Vector IS NULL
        THROW 50042, 'The external model returned no embedding.', 1;
    ;WITH Candidates AS
    (
    SELECT
        n.HistoricalNoteId, n.SourceCode, n.PersonId, n.RecordedAt,
        n.Title, n.AuthoredBy, n.NoteText, n.IsSynthetic, e.ModelId,
        results.distance AS CosineDistance,
        CONVERT(varchar(18), CONVERT(binary(8), n.NoteVersion), 1) AS SourceVersion,
        MIN(results.distance) OVER () AS BestDistance
    FROM VECTOR_SEARCH(
        TABLE = ai.HistoricalNoteEmbedding AS e,
        COLUMN = Embedding,
        SIMILAR_TO = @Vector,
        METRIC = 'cosine',
        TOP_N = @Candidates
    ) AS results
    JOIN care.HistoricalNote AS n ON n.HistoricalNoteId = e.HistoricalNoteId
    WHERE n.PersonId = @PersonId AND n.RecordedAt < @TransferStartedAt
      AND e.ModelId = 'nemotron-3-embed-1b-bf16'
      AND e.ContentHash = HASHBYTES('SHA2_256', CONVERT(nvarchar(max), N'passage: ') + n.NoteText)
    )
    -- Calibrated for this model and demo corpus, not clinical confidence.
    SELECT TOP (@TopK)
        HistoricalNoteId, SourceCode, PersonId, RecordedAt,
        Title, AuthoredBy, NoteText, IsSynthetic, ModelId,
        CosineDistance, SourceVersion
    FROM Candidates
    WHERE CosineDistance <= 0.82
      AND CosineDistance <= BestDistance + 0.10
    ORDER BY CosineDistance, HistoricalNoteId;
END;
GO

CREATE OR ALTER PROCEDURE ai.usp_RefreshHistoricalNoteEmbeddings
    @PersonId bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @PersonId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM care.Person WHERE PersonId = @PersonId)
        THROW 50043, 'Unknown person for embedding refresh.', 1;
    CREATE TABLE #EmbeddingWork (
        HistoricalNoteId bigint PRIMARY KEY, NoteText nvarchar(4000),
        ContentHash binary(32), Embedding VECTOR(2048, float16));
    INSERT #EmbeddingWork (HistoricalNoteId, NoteText, ContentHash)
    SELECT n.HistoricalNoteId, n.NoteText,
        HASHBYTES('SHA2_256', CONVERT(nvarchar(max), N'passage: ') + n.NoteText)
    FROM care.HistoricalNote AS n
    LEFT JOIN ai.HistoricalNoteEmbedding AS e ON e.HistoricalNoteId = n.HistoricalNoteId
    WHERE (@PersonId IS NULL OR n.PersonId = @PersonId)
      AND (e.HistoricalNoteId IS NULL
           OR e.ContentHash <> HASHBYTES('SHA2_256', CONVERT(nvarchar(max), N'passage: ') + n.NoteText)
           OR e.ModelId <> 'nemotron-3-embed-1b-bf16');
    IF @@TRANCOUNT <> 0 AND
       (EXISTS (SELECT 1 FROM #EmbeddingWork)
        OR (EXISTS (SELECT 1 FROM ai.HistoricalNoteEmbedding)
            AND NOT EXISTS (SELECT 1 FROM sys.indexes
                            WHERE object_id = OBJECT_ID(N'ai.HistoricalNoteEmbedding')
                              AND name = N'IX_HistoricalNoteEmbedding_Vector')))
        THROW 50058, 'Embedding refresh must run outside a user transaction to rebuild the vector index.', 1;
    DECLARE @Id bigint, @Input nvarchar(max), @Vector VECTOR(2048, float16);
    DECLARE notes CURSOR LOCAL FAST_FORWARD FOR
        SELECT HistoricalNoteId, CONVERT(nvarchar(max), N'passage: ') + NoteText FROM #EmbeddingWork;
    OPEN notes;
    FETCH NEXT FROM notes INTO @Id, @Input;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Vector = CAST(
            AI_GENERATE_EMBEDDINGS(@Input USE MODEL CaldovaHistoryEmbeddingModel)
            AS VECTOR(2048, float16));
        IF @Vector IS NULL
            THROW 50042, 'The external model returned no embedding.', 1;
        UPDATE #EmbeddingWork SET Embedding = @Vector WHERE HistoricalNoteId = @Id;
        FETCH NEXT FROM notes INTO @Id, @Input;
    END;
    CLOSE notes;
    DEALLOCATE notes;

    IF EXISTS (SELECT 1 FROM #EmbeddingWork)
    BEGIN
        -- This SQL Server preview makes vector-indexed tables read-only.
        IF EXISTS (SELECT 1 FROM sys.indexes
                   WHERE object_id = OBJECT_ID(N'ai.HistoricalNoteEmbedding')
                     AND name = N'IX_HistoricalNoteEmbedding_Vector')
            DROP INDEX IX_HistoricalNoteEmbedding_Vector ON ai.HistoricalNoteEmbedding;
        BEGIN TRY
            BEGIN TRANSACTION;
            IF EXISTS (
                SELECT 1 FROM #EmbeddingWork AS w
                LEFT JOIN care.HistoricalNote AS n WITH (UPDLOCK, HOLDLOCK)
                  ON n.HistoricalNoteId = w.HistoricalNoteId
                WHERE n.HistoricalNoteId IS NULL
                   OR HASHBYTES('SHA2_256', CONVERT(nvarchar(max), N'passage: ') + n.NoteText) <> w.ContentHash)
                THROW 50044, 'Historical note changed during inference; rerun refresh.', 1;
            -- Bind writes only after the read-only vector index has been dropped.
            EXEC sys.sp_executesql N'
            UPDATE e SET ModelId = ''nemotron-3-embed-1b-bf16'', ContentHash = w.ContentHash,
                Embedding = w.Embedding, EmbeddedAt = SYSUTCDATETIME()
            FROM ai.HistoricalNoteEmbedding AS e JOIN #EmbeddingWork AS w ON w.HistoricalNoteId = e.HistoricalNoteId;
            INSERT ai.HistoricalNoteEmbedding
                (HistoricalNoteId, ModelId, ContentHash, Embedding, EmbeddedAt)
            SELECT w.HistoricalNoteId, ''nemotron-3-embed-1b-bf16'', w.ContentHash, w.Embedding, SYSUTCDATETIME()
            FROM #EmbeddingWork AS w
            WHERE NOT EXISTS (SELECT 1 FROM ai.HistoricalNoteEmbedding AS e
                              WHERE e.HistoricalNoteId = w.HistoricalNoteId);';
            COMMIT;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK;
            IF EXISTS (SELECT 1 FROM ai.HistoricalNoteEmbedding)
                CREATE VECTOR INDEX IX_HistoricalNoteEmbedding_Vector
                    ON ai.HistoricalNoteEmbedding(Embedding)
                    WITH (METRIC = 'cosine', TYPE = 'DiskANN', MAXDOP = 1);
            THROW;
        END CATCH;
    END;
    IF EXISTS (SELECT 1 FROM ai.HistoricalNoteEmbedding)
       AND NOT EXISTS (SELECT 1 FROM sys.indexes
                       WHERE object_id = OBJECT_ID(N'ai.HistoricalNoteEmbedding')
                         AND name = N'IX_HistoricalNoteEmbedding_Vector')
        CREATE VECTOR INDEX IX_HistoricalNoteEmbedding_Vector
            ON ai.HistoricalNoteEmbedding(Embedding)
            WITH (METRIC = 'cosine', TYPE = 'DiskANN', MAXDOP = 1);
    SELECT COUNT(*) AS RefreshedNotes FROM #EmbeddingWork;
END;
GO
