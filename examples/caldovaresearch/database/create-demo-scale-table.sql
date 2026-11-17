/*
    Optional lower-cost corpus for local rehearsal.

    The public default uses the existing indexed dbo.pmc_chunks_1M table. Run this
    script only when 10,000 or 100,000 rows are more appropriate for your database.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @DeploymentApproved BIT = 0;
DECLARE @TargetRows INT = 100000;

IF @DeploymentApproved <> 1
    THROW 51300, 'Deployment is blocked. Review @TargetRows, then set @DeploymentApproved = 1.', 1;

IF @TargetRows NOT IN (10000, 100000)
    THROW 51301, '@TargetRows must be 10000 or 100000.', 1;

IF OBJECT_ID(N'dbo.pmc_chunks_1M', N'U') IS NULL
    THROW 51302, 'dbo.pmc_chunks_1M is required as the source table.', 1;

IF OBJECT_ID(N'dbo.pmc_chunks_demo', N'U') IS NOT NULL
    DROP TABLE dbo.pmc_chunks_demo;

SELECT TOP (@TargetRows)
       source_chunk.document_id,
       source_chunk.chunk_number,
       source_chunk.text_chunk,
       source_chunk.embedding
INTO dbo.pmc_chunks_demo
FROM dbo.pmc_chunks_1M AS source_chunk
ORDER BY source_chunk.document_id,
         source_chunk.chunk_number;

ALTER TABLE dbo.pmc_chunks_demo
    ADD CONSTRAINT PK_pmc_chunks_demo
        PRIMARY KEY CLUSTERED (document_id, chunk_number);

CREATE VECTOR INDEX vidx_embedding_demo
    ON dbo.pmc_chunks_demo (embedding)
    WITH (METRIC = 'COSINE', TYPE = 'DISKANN');

IF DATABASE_PRINCIPAL_ID(N'CaldovaSearchReader') IS NOT NULL
    GRANT SELECT ON OBJECT::dbo.pmc_chunks_demo TO CaldovaSearchReader;

SELECT COUNT_BIG(*) AS DemoRowCount
FROM dbo.pmc_chunks_demo;