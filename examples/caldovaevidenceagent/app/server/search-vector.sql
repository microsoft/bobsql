/*
    Vector-only retrieval for the scale targets.

    __CHUNKS_TABLE__ is replaced by the server from a fixed allowlist. SQL Server
    table identifiers cannot be supplied as query parameters.
*/

SET NOCOUNT ON;

DECLARE @QueryVector VECTOR(512) = CAST(@queryVectorJson AS VECTOR(512));
DECLARE @VectorStart DATETIME2(7) = SYSUTCDATETIME();
DECLARE @VectorMicroseconds BIGINT;

DECLARE @VectorCandidates TABLE
(
    document_id INT NOT NULL,
    chunk_number INT NOT NULL,
    Distance FLOAT NOT NULL,
    Position INT NOT NULL
);

INSERT @VectorCandidates (document_id, chunk_number, Distance, Position)
SELECT ranked.document_id,
       ranked.chunk_number,
       ranked.Distance,
       ROW_NUMBER() OVER (ORDER BY ranked.Distance)
FROM
(
    SELECT TOP (@candidates) WITH APPROXIMATE
           chunk.document_id,
           chunk.chunk_number,
           vector_result.distance AS Distance
    FROM VECTOR_SEARCH
    (
        TABLE = __CHUNKS_TABLE__ AS chunk,
        COLUMN = embedding,
        SIMILAR_TO = @QueryVector,
        METRIC = 'COSINE'
    ) AS vector_result
    ORDER BY vector_result.distance
) AS ranked;

SET @VectorMicroseconds = DATEDIFF_BIG(microsecond, @VectorStart, SYSUTCDATETIME());

WITH BestPerDocument AS
(
    SELECT candidate.document_id,
           candidate.chunk_number,
           candidate.Distance,
           candidate.Position,
           ROW_NUMBER() OVER
           (
               PARTITION BY candidate.document_id
               ORDER BY candidate.Distance
           ) AS DocumentRank
    FROM @VectorCandidates AS candidate
)
SELECT TOP (@top)
       CONCAT('PMC', document.pmcid) AS PmcId,
       document.title AS Title,
       best.chunk_number AS ChunkNumber,
       best.Distance,
       1.0 / (60.0 + best.Position) AS Score,
       CAST(@VectorMicroseconds AS FLOAT) / 1000.0 AS VectorSearchMs,
       previous_chunk.text_chunk AS PreviousPassage,
       chunk.text_chunk AS Passage,
       next_chunk.text_chunk AS NextPassage
FROM BestPerDocument AS best
INNER JOIN __CHUNKS_TABLE__ AS chunk
    ON chunk.document_id = best.document_id
   AND chunk.chunk_number = best.chunk_number
INNER JOIN dbo.pmc_documents AS document
    ON document.document_id = best.document_id
LEFT JOIN __CHUNKS_TABLE__ AS previous_chunk
    ON previous_chunk.document_id = best.document_id
   AND previous_chunk.chunk_number = best.chunk_number - 1
LEFT JOIN __CHUNKS_TABLE__ AS next_chunk
    ON next_chunk.document_id = best.document_id
   AND next_chunk.chunk_number = best.chunk_number + 1
WHERE best.DocumentRank = 1
  AND chunk.text_chunk IS NOT NULL
ORDER BY best.Distance;