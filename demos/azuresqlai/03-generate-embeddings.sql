-- ============================================================================
-- 03-generate-embeddings.sql
-- Generates vector embeddings for all rows using AI_GENERATE_EMBEDDINGS
-- with the external model created in script 01.
-- This uses the SQL server's managed identity to call Azure OpenAI.
-- ============================================================================

-- Generate embeddings for all rows that don't have them yet
-- AI_GENERATE_EMBEDDINGS calls Azure OpenAI via the external model
UPDATE t
SET embedding = AI_GENERATE_EMBEDDINGS(t.content USE MODEL EmbeddingModel)
FROM dbo.azure_sql_knowledge AS t
WHERE t.embedding IS NULL;
GO

-- Verify embeddings were generated
SELECT
    COUNT(*) AS total_rows,
    COUNT(embedding) AS rows_with_embeddings,
    COUNT(*) - COUNT(embedding) AS rows_without_embeddings
FROM dbo.azure_sql_knowledge;
GO

-- Preview a few rows with their embedding (truncated)
SELECT TOP 5
    id,
    title,
    category,
    LEFT(CAST(embedding AS NVARCHAR(MAX)), 100) + '...' AS embedding_preview
FROM dbo.azure_sql_knowledge
WHERE embedding IS NOT NULL;
GO
