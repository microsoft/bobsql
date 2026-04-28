-- ============================================================================
-- 04-create-vector-index.sql
-- Creates a DiskANN vector index for approximate nearest neighbor (ANN) search.
-- Requires at least 100 rows with non-NULL vector values.
-- ============================================================================

-- Verify we have enough rows with embeddings (need 100+)
SELECT COUNT(*) AS rows_with_embeddings
FROM dbo.azure_sql_knowledge
WHERE embedding IS NOT NULL;
GO

-- Create a DiskANN vector index on the embedding column
-- This enables approximate nearest neighbor search with high recall and low latency
CREATE VECTOR INDEX vec_idx_knowledge_embedding
    ON dbo.azure_sql_knowledge (embedding)
    WITH (METRIC = 'cosine', TYPE = 'DISKANN');
GO

-- Verify the vector index was created
SELECT
    i.name AS index_name,
    t.name AS table_name,
    JSON_VALUE(v.build_parameters, '$.Version') AS index_version,
    JSON_VALUE(v.build_parameters, '$.Metric') AS metric
FROM sys.vector_indexes AS v
    INNER JOIN sys.indexes AS i
        ON v.object_id = i.object_id AND v.index_id = i.index_id
    INNER JOIN sys.tables AS t
        ON v.object_id = t.object_id;
GO

-- Quick test: approximate search (ANN) using VECTOR_SEARCH with the DiskANN index
-- Capture the actual execution plan and verify a "Vector Index Seek" operator is used
DECLARE @qv VECTOR(1536) = AI_GENERATE_EMBEDDINGS(N'How do I scale my database?' USE MODEL EmbeddingModel);
DECLARE @plan_xml XML;

-- Get the estimated execution plan for the vector search query
SET @plan_xml = (
    SELECT query_plan
    FROM sys.dm_exec_query_plan((
        SELECT TOP 1 plan_handle
        FROM sys.dm_exec_query_stats
        CROSS APPLY sys.dm_exec_sql_text(sql_handle) AS st
        WHERE st.text LIKE '%VECTOR_SEARCH%azure_sql_knowledge%'
            AND st.text NOT LIKE '%dm_exec_query%'
        ORDER BY last_execution_time DESC
    ))
);

SELECT TOP(5) WITH APPROXIMATE
    t.id,
    t.title,
    t.category,
    s.distance
FROM VECTOR_SEARCH(
    TABLE = dbo.azure_sql_knowledge AS t,
    COLUMN = embedding,
    SIMILAR_TO = @qv,
    METRIC = 'cosine'
) AS s
ORDER BY s.distance;
GO

-- Check the cached execution plan for the vector search query
-- Look for "Vector Index Seek" in the plan XML
DECLARE @plan_xml XML;

SELECT TOP 1 @plan_xml = qp.query_plan
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
WHERE st.text LIKE '%VECTOR_SEARCH%azure_sql_knowledge%'
    AND st.text NOT LIKE '%dm_exec_query%'
ORDER BY qs.last_execution_time DESC;

-- Report whether the Vector Index Seek operator was used
IF @plan_xml IS NOT NULL
    AND CAST(@plan_xml AS NVARCHAR(MAX)) LIKE '%VectorIndexSeek%'
BEGIN
    SELECT 'PASS' AS plan_check,
           'Vector Index Seek found - DiskANN index is being used' AS detail;
END
ELSE IF @plan_xml IS NOT NULL
BEGIN
    SELECT 'FAIL' AS plan_check,
           'Vector Index Seek NOT found - query may be using brute-force scan' AS detail;
    -- Show the plan XML for debugging
    SELECT @plan_xml AS execution_plan;
END
ELSE
BEGIN
    SELECT 'WARNING' AS plan_check,
           'Could not retrieve cached plan - run the query above first, then re-run this check' AS detail;
END
GO
