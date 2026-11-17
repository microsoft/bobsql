/*
    Caldova retrieval.

    One statement covers all three modes. @useVector and @useKeyword select which
    retrievers contribute; when both are on, their ranks are fused with reciprocal
    rank fusion, which is the hybrid mode.

    The vector step is materialised on its own so it can be timed in-engine. That
    number is the ANN search itself, not the fusion, joins, or context expansion.

    Results are collapsed to the best passage per document, and each one carries the
    surrounding chunks so the quote reads as written.
*/

SET NOCOUNT ON;

DECLARE @QueryVector VECTOR(512) = CAST(@queryVectorJson AS VECTOR(512));
DECLARE @VectorStart DATETIME2(7);
DECLARE @VectorMicroseconds BIGINT = NULL;

DECLARE @VectorCandidates TABLE
(
    document_id INT NOT NULL,
    chunk_number INT NOT NULL,
    Distance FLOAT NOT NULL,
    Position INT NOT NULL
);

DECLARE @KeywordCandidates TABLE
(
    document_id INT NOT NULL,
    chunk_number INT NOT NULL,
    Position INT NOT NULL
);

IF @useVector = 1
BEGIN
    SET @VectorStart = SYSUTCDATETIME();

    INSERT @VectorCandidates (document_id, chunk_number, Distance, Position)
    SELECT ranked.document_id,
           ranked.chunk_number,
           ranked.Distance,
           ROW_NUMBER() OVER (ORDER BY ranked.Distance)
    FROM
    (
        -- APPROXIMATE cannot sit alongside a window function, so ranking happens outside.
        SELECT TOP (@candidates) WITH APPROXIMATE
               chunk.document_id,
               chunk.chunk_number,
               vector_result.distance AS Distance
        FROM VECTOR_SEARCH
        (
            TABLE = dbo.pmc_chunks AS chunk,
            COLUMN = embedding,
            SIMILAR_TO = @QueryVector,
            METRIC = 'COSINE'
        ) AS vector_result
        WHERE chunk.is_boilerplate = 0/*PEER_REVIEWED_FILTER*/
        ORDER BY vector_result.distance
    ) AS ranked;

    SET @VectorMicroseconds = DATEDIFF_BIG(microsecond, @VectorStart, SYSUTCDATETIME());
END;

IF @useKeyword = 1
BEGIN
    INSERT @KeywordCandidates (document_id, chunk_number, Position)
    SELECT TOP (@candidates)
           chunk.document_id,
           chunk.chunk_number,
           ROW_NUMBER() OVER (ORDER BY ranked.[RANK] DESC)
    FROM FREETEXTTABLE(dbo.pmc_chunks, text_chunk, @queryText, @candidates) AS ranked
    INNER JOIN dbo.pmc_chunks AS chunk
        ON chunk.chunk_id = ranked.[KEY]
    WHERE chunk.is_boilerplate = 0/*PEER_REVIEWED_FILTER*/
    ORDER BY ranked.[RANK] DESC;
END;

WITH Fused AS
(
    SELECT candidate.document_id,
           candidate.chunk_number,
           SUM(1.0 / (60.0 + candidate.Position)) AS Score,
           MIN(candidate.Distance) AS Distance
    FROM
    (
        SELECT document_id, chunk_number, Position, Distance FROM @VectorCandidates
        UNION ALL
        SELECT document_id, chunk_number, Position, NULL FROM @KeywordCandidates
    ) AS candidate
    GROUP BY candidate.document_id, candidate.chunk_number
),
BestPerDocument AS
(
    SELECT document_id,
           chunk_number,
           Score,
           Distance,
           ROW_NUMBER() OVER (PARTITION BY document_id ORDER BY Score DESC, chunk_number) AS DocumentRank
    FROM Fused
)
SELECT TOP (@top)
       CONCAT('PMC', document.pmcid) AS PmcId,
       document.title AS Title,
       best.chunk_number AS ChunkNumber,
       best.Distance AS Distance,
       best.Score AS Score,
       CONVERT(FLOAT, @VectorMicroseconds) / 1000.0 AS VectorSearchMs,
       previous_chunk.text_chunk AS PreviousPassage,
       chunk.text_chunk AS Passage,
       next_chunk.text_chunk AS NextPassage
FROM BestPerDocument AS best
INNER JOIN dbo.pmc_chunks AS chunk
    ON chunk.document_id = best.document_id
   AND chunk.chunk_number = best.chunk_number
INNER JOIN dbo.pmc_documents AS document
    ON document.document_id = best.document_id
LEFT JOIN dbo.pmc_chunks AS previous_chunk
    ON previous_chunk.document_id = best.document_id
   AND previous_chunk.chunk_number = best.chunk_number - 1
LEFT JOIN dbo.pmc_chunks AS next_chunk
    ON next_chunk.document_id = best.document_id
   AND next_chunk.chunk_number = best.chunk_number + 1
WHERE best.DocumentRank = 1
ORDER BY best.Score DESC;
