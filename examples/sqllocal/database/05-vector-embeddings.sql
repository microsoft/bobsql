USE CaldovaRegionalCare;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE TABLE ai.HistoricalNoteEmbedding
(
    EmbeddingId int IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_HistoricalNoteEmbedding PRIMARY KEY CLUSTERED,
    HistoricalNoteId bigint NOT NULL CONSTRAINT UQ_HistoricalNoteEmbedding_Note UNIQUE
        REFERENCES care.HistoricalNote(HistoricalNoteId),
    ModelId varchar(100) NOT NULL,
    ContentHash binary(32) NOT NULL,
    Embedding VECTOR(2048, float16) NOT NULL,
    EmbeddedAt datetime2(3) NOT NULL
);
GO

INSERT ai.HistoricalNoteEmbedding
    (HistoricalNoteId, ModelId, ContentHash, Embedding, EmbeddedAt)
SELECT n.HistoricalNoteId, 'nemotron-3-embed-1b-bf16',
    HASHBYTES('SHA2_256', CONVERT(nvarchar(max), N'passage: ') + n.NoteText),
    CAST(AI_GENERATE_EMBEDDINGS(
        (CONVERT(nvarchar(max), N'passage: ') + n.NoteText)
        USE MODEL CaldovaHistoryEmbeddingModel) AS VECTOR(2048, float16)),
    SYSUTCDATETIME()
FROM care.HistoricalNote AS n;
GO

CREATE VECTOR INDEX IX_HistoricalNoteEmbedding_Vector
    ON ai.HistoricalNoteEmbedding(Embedding)
    WITH (METRIC = 'cosine', TYPE = 'DiskANN', MAXDOP = 1);
GO
