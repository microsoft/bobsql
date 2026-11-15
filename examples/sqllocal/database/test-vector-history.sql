USE CaldovaRegionalCare;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF NOT EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'CaldovaHistoryEmbeddingModel')
    THROW 50049, 'Expected the native Caldova history external model.', 1;
EXEC ai.usp_RefreshHistoricalNoteEmbeddings;
IF (SELECT COUNT(*) FROM ai.HistoricalNoteEmbedding) < 7
    THROW 50049, 'Expected at least seven persisted note embeddings.', 1;
IF EXISTS (SELECT 1 FROM ai.HistoricalNoteEmbedding
           WHERE DATALENGTH(Embedding) <> 4104
              OR ContentHash <> (SELECT HASHBYTES('SHA2_256', CONVERT(nvarchar(max), N'passage: ') + NoteText)
                                 FROM care.HistoricalNote AS n
                                 WHERE n.HistoricalNoteId = ai.HistoricalNoteEmbedding.HistoricalNoteId))
    THROW 50049, 'Embedding dimensions or source hashes are invalid.', 1;

DECLARE @Repeat TABLE (RefreshedNotes int);
INSERT @Repeat EXEC ai.usp_RefreshHistoricalNoteEmbeddings;
IF (SELECT RefreshedNotes FROM @Repeat) <> 0
    THROW 50049, 'Repeat refresh unexpectedly regenerated unchanged notes.', 1;

DECLARE @NoteId bigint, @OriginalHash binary(32), @PreviousEmbeddedAt datetime2(3);
SELECT @NoteId = e.HistoricalNoteId, @OriginalHash = e.ContentHash, @PreviousEmbeddedAt = e.EmbeddedAt
FROM ai.HistoricalNoteEmbedding AS e
JOIN care.HistoricalNote AS n ON n.HistoricalNoteId = e.HistoricalNoteId
WHERE n.SourceCode = 'DEMO-MARIA-ALLERGY';
BEGIN TRY
    DROP INDEX IX_HistoricalNoteEmbedding_Vector ON ai.HistoricalNoteEmbedding;
    BEGIN TRY
        EXEC ai.usp_SearchTransferHistory 'TR-2026-0147', N'aspirin', 1;
        THROW 50049, 'Search must reject a missing vector index rather than fall back to exact search.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> 42227 THROW;
    END CATCH;
    EXEC sys.sp_executesql
        N'UPDATE ai.HistoricalNoteEmbedding SET ContentHash = 0x00 WHERE HistoricalNoteId = @Id;',
        N'@Id bigint', @NoteId;
    CREATE VECTOR INDEX IX_HistoricalNoteEmbedding_Vector
        ON ai.HistoricalNoteEmbedding(Embedding)
        WITH (METRIC = 'cosine', TYPE = 'DiskANN', MAXDOP = 1);
    EXEC ai.usp_RefreshHistoricalNoteEmbeddings;
    IF NOT EXISTS (SELECT 1 FROM ai.HistoricalNoteEmbedding
                   WHERE HistoricalNoteId = @NoteId AND ContentHash = @OriginalHash
                     AND EmbeddedAt > @PreviousEmbeddedAt)
        THROW 50049, 'Refresh did not regenerate the stale embedding using the native model.', 1;
    IF NOT EXISTS (SELECT 1 FROM sys.indexes
                   WHERE object_id = OBJECT_ID(N'ai.HistoricalNoteEmbedding')
                     AND name = N'IX_HistoricalNoteEmbedding_Vector' AND type_desc = N'VECTOR')
        THROW 50049, 'Refresh did not restore the genuine vector index.', 1;
END TRY
BEGIN CATCH
    IF EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID(N'ai.HistoricalNoteEmbedding')
                 AND name = N'IX_HistoricalNoteEmbedding_Vector')
        DROP INDEX IX_HistoricalNoteEmbedding_Vector ON ai.HistoricalNoteEmbedding;
    EXEC sys.sp_executesql
        N'UPDATE ai.HistoricalNoteEmbedding SET ContentHash = @Hash WHERE HistoricalNoteId = @Id;',
        N'@Id bigint, @Hash binary(32)', @NoteId, @OriginalHash;
    EXEC ai.usp_RefreshHistoricalNoteEmbeddings;
    THROW;
END CATCH;

DECLARE @Results TABLE
(
    HistoricalNoteId bigint, SourceCode varchar(60), PersonId bigint,
    RecordedAt datetime2(3), Title nvarchar(200), AuthoredBy nvarchar(200),
    NoteText nvarchar(4000), IsSynthetic bit, ModelId varchar(100), CosineDistance float,
    SourceVersion varchar(18)
);
INSERT @Results EXEC ai.usp_SearchTransferHistory
    @TransferNumber = 'TR-2026-0147',
    @Query = N'What was previously recorded about a reaction to aspirin?',
    @TopK = 3;
IF (SELECT COUNT(*) FROM @Results) <> 1
    THROW 50049, 'Aspirin search must not fill TopK with unrelated notes.', 1;
IF EXISTS (SELECT 1 FROM @Results AS r JOIN care.Person AS p ON p.PersonId = r.PersonId
           WHERE p.RegionalRecordNumber <> 'CR-804921')
    THROW 50049, 'Search leaked another patient history.', 1;
IF (SELECT TOP (1) SourceCode FROM @Results ORDER BY CosineDistance, HistoricalNoteId)
    <> 'DEMO-MARIA-ALLERGY'
    THROW 50049, 'Aspirin reaction search did not rank the allergy note first.', 1;
SELECT SourceCode, RecordedAt, Title, CosineDistance FROM @Results ORDER BY CosineDistance, HistoricalNoteId;

DELETE FROM @Results;
INSERT @Results EXEC ai.usp_SearchTransferHistory
    @TransferNumber = 'TR-2026-0147',
    @Query = N'Previous chest discomfort with nausea during exertion',
    @TopK = 3;
IF (SELECT COUNT(*) FROM @Results) <> 1
    OR NOT EXISTS (SELECT 1 FROM @Results WHERE SourceCode = 'DEMO-MARIA-CHEST')
    THROW 50049, 'Chest discomfort search did not rank the prior chest note first.', 1;
SELECT SourceCode, RecordedAt, Title, CosineDistance FROM @Results;

DECLARE @RelevanceCases TABLE
(
    Id int IDENTITY PRIMARY KEY,
    TransferNumber varchar(30), QueryText nvarchar(4000), ExpectedSource varchar(60)
);
INSERT @RelevanceCases (TransferNumber, QueryText, ExpectedSource) VALUES
('TR-2026-0147', N'chest pressure', 'DEMO-MARIA-CHEST'),
('TR-2026-0147', N'pressure in my chest when climbing stairs', 'DEMO-MARIA-CHEST'),
('TR-2026-0147', N'tight squeezing feeling in the center of the chest on exertion', 'DEMO-MARIA-CHEST'),
('TR-2026-0147', N'chrest prssure', 'DEMO-MARIA-CHEST'),
('TR-2026-0147', N'Which medicines was the patient taking?', 'DEMO-MARIA-MEDICATION'),
('TR-2026-0147', N'walking aid for knee pain', 'DEMO-MARIA-MOBILITY'),
('TR-2026-0147', N'preferred language and interpreter', 'DEMO-MARIA-CONTACT'),
('TR-2026-0149', N'Shortness of breath', 'DEMO-ELENA-BREATHING'),
('TR-2026-0148', N'Lower leg injury', NULL),
('TR-2026-0147', N'broken wrist', NULL),
('TR-2026-0147', N'kidney stones and blood in urine', NULL),
('TR-2026-0147', N'weather forecast tomorrow', NULL);
DECLARE @CaseId int = 1, @Transfer varchar(30), @SearchQuery nvarchar(4000),
    @ExpectedSource varchar(60);
WHILE @CaseId <= (SELECT COUNT(*) FROM @RelevanceCases)
BEGIN
    SELECT @Transfer = TransferNumber, @SearchQuery = QueryText,
        @ExpectedSource = ExpectedSource FROM @RelevanceCases WHERE Id = @CaseId;
    DELETE FROM @Results;
    INSERT @Results EXEC ai.usp_SearchTransferHistory @Transfer, @SearchQuery, 3;
    IF (@ExpectedSource IS NULL AND EXISTS (SELECT 1 FROM @Results))
       OR (@ExpectedSource IS NOT NULL AND
           ((SELECT COUNT(*) FROM @Results) <> 1
            OR NOT EXISTS (SELECT 1 FROM @Results WHERE SourceCode = @ExpectedSource)))
    BEGIN
        DECLARE @RelevanceError nvarchar(2048) = N'Unexpected relevance results for: ' + @SearchQuery;
        THROW 50049, @RelevanceError, 1;
    END;
    SET @CaseId += 1;
END;

BEGIN TRY
    EXEC ai.usp_SearchTransferHistory 'TR-DOES-NOT-EXIST', N'aspirin', 1;
    THROW 50049, 'Unknown transfer should have failed.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 50046 THROW;
END CATCH;
BEGIN TRY
    EXEC ai.usp_SearchTransferHistory 'TR-2026-0147', N'aspirin', 0;
    THROW 50049, 'Invalid TopK should have failed.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 50045 THROW;
END CATCH;
BEGIN TRY
    EXEC ai.usp_SearchTransferHistory 'TR-2026-0147', N' ', 1;
    THROW 50049, 'Empty query should have failed.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 50041 THROW;
END CATCH;

BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE care.HistoricalNote SET NoteText = N'[Stale-source test] ' + NoteText
    WHERE SourceCode = 'DEMO-MARIA-ALLERGY';
    EXEC ai.usp_SearchTransferHistory 'TR-2026-0147', N'aspirin', 1;
    THROW 50049, 'Stale embedding should have failed.', 1;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    IF ERROR_NUMBER() <> 50047 THROW;
END CATCH;

SELECT N'Vector history tests passed' AS Result,
    (SELECT COUNT(*) FROM ai.ModelEndpoint WHERE IsActive = 1 AND ModelId = N'gpt-oss-20b')
        AS ActiveGptBriefingEndpoints;
GO
