USE CustomerServiceDesk;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;

IF (SELECT COUNT(*) FROM dbo.CaseEmbeddings) < 100
    THROW 51103, 'At least 100 real case embeddings are required before building DiskANN.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID(N'dbo.CaseEmbeddings') AND name = N'IX_CaseEmbeddings_Vector')
    CREATE VECTOR INDEX IX_CaseEmbeddings_Vector ON dbo.CaseEmbeddings(Embedding)
        WITH (METRIC = 'cosine', TYPE = 'DiskANN');
IF NOT EXISTS
(
    SELECT 1 FROM sys.vector_indexes
    WHERE object_id = OBJECT_ID(N'dbo.CaseEmbeddings') AND name = N'IX_CaseEmbeddings_Vector'
      AND TRY_CONVERT(int, JSON_VALUE(build_parameters, '$.Version')) >= 3
)
    THROW 51103, 'Expected a version 3-or-later DiskANN index; no automatic replacement was attempted.', 1;
