SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.search_evidence
    @question NVARCHAR(4000),
    @top_k INT = 5
AS
BEGIN
    SET NOCOUNT ON;

    SET @question = NULLIF(TRIM(@question), N'');
    IF @question IS NULL
        THROW 51010, 'question is required.', 1;
    IF @top_k < 1 OR @top_k > 10
        THROW 51011, 'top_k must be between 1 and 10.', 1;

    DECLARE @query_vector VECTOR(512) =
        AI_GENERATE_EMBEDDINGS(@question USE MODEL CaldovaEvidenceEmbedding);
    IF @query_vector IS NULL
        THROW 51012, 'The embedding model returned NULL.', 1;

    DECLARE @candidate_count INT = @top_k * 8;

    WITH Candidate AS
    (
        SELECT TOP (@candidate_count) WITH APPROXIMATE
            chunk.document_id,
            chunk.chunk_number,
            chunk.text_chunk,
            search_result.distance
        FROM VECTOR_SEARCH(
            TABLE = dbo.pmc_chunks AS chunk,
            COLUMN = embedding,
            SIMILAR_TO = @query_vector,
            METRIC = 'cosine'
        ) AS search_result
        WHERE chunk.embedding IS NOT NULL
        ORDER BY search_result.distance
    ),
    RankedArticle AS
    (
        SELECT
            candidate.*,
            ROW_NUMBER() OVER
            (
                PARTITION BY candidate.document_id
                ORDER BY candidate.distance, candidate.chunk_number
            ) AS article_rank
        FROM Candidate AS candidate
    )
    SELECT TOP (@top_k)
        document.pmcid,
        document.title,
        ranked.chunk_number,
        ranked.text_chunk AS passage,
        previous_chunk.text_chunk AS previous_passage,
        next_chunk.text_chunk AS next_passage,
        ranked.distance,
        CONCAT(N'https://pmc.ncbi.nlm.nih.gov/articles/', document.pmcid, N'/') AS source_url
    FROM RankedArticle AS ranked
    INNER JOIN dbo.pmc_documents AS document
        ON document.document_id = ranked.document_id
    LEFT JOIN dbo.pmc_chunks AS previous_chunk
        ON previous_chunk.document_id = ranked.document_id
       AND previous_chunk.chunk_number = ranked.chunk_number - 1
    LEFT JOIN dbo.pmc_chunks AS next_chunk
        ON next_chunk.document_id = ranked.document_id
       AND next_chunk.chunk_number = ranked.chunk_number + 1
    WHERE ranked.article_rank = 1
    ORDER BY ranked.distance, document.pmcid;
END;
GO

CREATE OR ALTER PROCEDURE dbo.get_article_context
    @pmcid NVARCHAR(32),
    @chunk_number INT,
    @radius INT = 2
AS
BEGIN
    SET NOCOUNT ON;

    SET @pmcid = NULLIF(TRIM(@pmcid), N'');
    IF @pmcid IS NULL
        THROW 51020, 'pmcid is required.', 1;
    IF @chunk_number < 0
        THROW 51021, 'chunk_number must be zero or greater.', 1;
    IF @radius < 0 OR @radius > 5
        THROW 51022, 'radius must be between 0 and 5.', 1;

    SELECT
        document.pmcid,
        document.title,
        chunk.chunk_number,
        chunk.text_chunk AS passage,
        CONCAT(N'https://pmc.ncbi.nlm.nih.gov/articles/', document.pmcid, N'/') AS source_url
    FROM dbo.pmc_documents AS document
    INNER JOIN dbo.pmc_chunks AS chunk
        ON chunk.document_id = document.document_id
    WHERE document.pmcid = @pmcid
      AND chunk.chunk_number BETWEEN @chunk_number - @radius AND @chunk_number + @radius
    ORDER BY chunk.chunk_number;
END;
GO

CREATE OR ALTER PROCEDURE dbo.get_corpus_status
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        status.corpus_version,
        (SELECT COUNT_BIG(*) FROM dbo.pmc_documents) AS article_count,
        (SELECT COUNT_BIG(*) FROM dbo.pmc_chunks) AS passage_count,
        (SELECT COUNT_BIG(*) FROM dbo.pmc_chunks WHERE embedding IS NOT NULL) AS embedded_passage_count,
        status.embedding_model,
        status.embedding_dimensions,
        index_definition.name AS vector_index_name,
        JSON_VALUE(vector_index.build_parameters, '$.Version') AS vector_index_version,
        vector_index.distance_metric,
        status.loaded_at,
        status.embedded_at
    FROM dbo.corpus_status AS status
    LEFT JOIN sys.indexes AS index_definition
        ON index_definition.object_id = OBJECT_ID(N'dbo.pmc_chunks')
       AND index_definition.name = N'IX_pmc_chunks_embedding'
    LEFT JOIN sys.vector_indexes AS vector_index
        ON vector_index.object_id = index_definition.object_id
       AND vector_index.index_id = index_definition.index_id
    WHERE status.status_id = 1;
END;
GO

GRANT EXECUTE ON OBJECT::dbo.search_evidence TO CaldovaEvidenceReader;
GRANT EXECUTE ON OBJECT::dbo.get_article_context TO CaldovaEvidenceReader;
GRANT EXECUTE ON OBJECT::dbo.get_corpus_status TO CaldovaEvidenceReader;
GRANT EXECUTE ON EXTERNAL MODEL::CaldovaEvidenceEmbedding TO CaldovaEvidenceReader;
GO
