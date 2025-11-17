USE [AdventureWorks];
GO
CREATE OR ALTER PROCEDURE dbo.measure_vector_search_recall
    @prompt           nvarchar(max),               -- NL query
    @stock            smallint        = 500,       -- min SafetyStockLevel
    @top              int             = 10,        -- K for both methods
    @min_similarity   decimal(19,16)  = 0.3        -- threshold on similarity = 1 - distance
AS
BEGIN
    SET NOCOUNT ON;
    IF (@prompt IS NULL) RETURN;

    DECLARE @qemb vector(384);

    -- Create query embedding with your model (same pattern you used)
    SELECT @qemb = AI_GENERATE_EMBEDDINGS(@prompt USE MODEL MyLocalONNXModel);

    ;WITH
    ----------------------------------------------------------------------
    -- Exact KNN baseline using VECTOR_DISTANCE (top K by lowest distance)
    ----------------------------------------------------------------------
    exact_knn AS
    (
        SELECT TOP (@top)
            pe.ProductDescEmbeddingID,
            pe.ProductID,
            VECTOR_DISTANCE('cosine', pe.Embedding, @qemb) AS distance
        FROM Production.ProductDescriptionEmbeddings AS pe
        JOIN Production.Product AS p
          ON p.ProductID = pe.ProductID
        WHERE p.SafetyStockLevel >= @stock
        ORDER BY VECTOR_DISTANCE('cosine', pe.Embedding, @qemb) ASC
    ),
    exact_top AS
    (
        -- Apply similarity threshold on the exact distances
        SELECT ProductDescEmbeddingID, ProductID, distance
        FROM exact_knn
        WHERE (1.0 - distance) > @min_similarity
    ),

    ----------------------------------------------------------------------
    -- ANN search using VECTOR_SEARCH (uses DiskANN index if present)
    ----------------------------------------------------------------------
    ann_raw AS
    (
        SELECT
            e.ProductDescEmbeddingID,
            e.ProductID,
            vs.distance
        FROM VECTOR_SEARCH(
                TABLE      = Production.ProductDescriptionEmbeddings AS e,
                COLUMN     = Embedding,
                SIMILAR_TO = @qemb,
                METRIC     = 'cosine',
                TOP_N      = @top
             ) AS vs
        JOIN Production.Product AS p
          ON p.ProductID = e.ProductID
        WHERE p.SafetyStockLevel >= @stock
    ),
    ann_top AS
    (
        -- Apply the same similarity threshold
        SELECT ProductDescEmbeddingID, ProductID, distance
        FROM ann_raw
        WHERE (1.0 - distance) > @min_similarity
    ),

    ----------------------------------------------------------------------
    -- Overlap and counts for recall
    ----------------------------------------------------------------------
    overlap AS
    (
        SELECT a.ProductDescEmbeddingID
        FROM ann_top a
        INNER JOIN exact_top e
            ON e.ProductDescEmbeddingID = a.ProductDescEmbeddingID
    ),
    counts AS
    (
        SELECT
            (SELECT COUNT(*) FROM exact_top)    AS exact_k,
            (SELECT COUNT(*) FROM ann_top)      AS ann_k,
            (SELECT COUNT(*) FROM overlap)      AS overlap_k
    )
    SELECT
        -- recall = overlap / exact_k ; protect against divide-by-zero
        CAST(CASE WHEN exact_k = 0 THEN 0.0
                  ELSE overlap_k * 1.0 / exact_k END AS decimal(6,4)) AS recall
        -- Optional diagnostics (uncomment if you want them)
        --, exact_k AS exact_count
        --, ann_k   AS ann_count
        --, overlap_k AS overlap_count
    FROM counts;
END
GO

-- Give it a spin
EXEC measure_vector_search_recall
@prompt = N'I want a gliding, pillow‑y feel on battered streets, zero buzz through the hands.',
@stock = 100, 
@top = 10;
GO