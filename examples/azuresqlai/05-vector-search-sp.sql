-- ============================================================================
-- 05-vector-search-sp.sql
-- Creates a stored procedure for approximate vector search using
-- VECTOR_SEARCH with TOP WITH APPROXIMATE and the DiskANN index.
-- ============================================================================

CREATE OR ALTER PROCEDURE dbo.usp_vector_search
    @search_text NVARCHAR(MAX),
    @top_n INT = 5
AS
BEGIN
    SET NOCOUNT ON;

    -- Generate embedding for the search query
    DECLARE @qv VECTOR(1536) = AI_GENERATE_EMBEDDINGS(@search_text USE MODEL EmbeddingModel);

    -- Perform approximate nearest neighbor search using the DiskANN vector index
    -- TOP WITH APPROXIMATE leverages the vector index for fast retrieval
    SELECT TOP(@top_n) WITH APPROXIMATE
        t.id,
        t.title,
        t.category,
        t.content,
        s.distance
    FROM VECTOR_SEARCH(
        TABLE = dbo.azure_sql_knowledge AS t,
        COLUMN = embedding,
        SIMILAR_TO = @qv,
        METRIC = 'cosine'
    ) AS s
    ORDER BY s.distance;
END
GO

-- Test the vector search stored procedure with various queries
EXEC dbo.usp_vector_search @search_text = N'What security features protect my data?';
GO

EXEC dbo.usp_vector_search @search_text = N'How can I use AI and machine learning with my database?';
GO

EXEC dbo.usp_vector_search @search_text = N'What options are available for disaster recovery?', @top_n = 3;
GO

EXEC dbo.usp_vector_search @search_text = N'Tell me about serverless and auto-scaling';
GO
