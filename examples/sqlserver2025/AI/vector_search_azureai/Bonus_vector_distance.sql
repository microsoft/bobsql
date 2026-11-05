USE [AdventureWorks];
GO
CREATE OR ALTER PROCEDURE [dbo].[find_relevant_products_vector_precise]
    @prompt          nvarchar(max),     -- NL prompt
    @stock           smallint      = 500,  -- Only show products with stock >= @stock
    @top             int           = 10,   -- Top K results to return
    @min_similarity  decimal(19,16) = 0.3  -- Cosine similarity threshold (1 - cosine distance)
AS
BEGIN
    SET NOCOUNT ON;

    IF @prompt IS NULL OR LTRIM(RTRIM(@prompt)) = N'' RETURN;

    DECLARE @vector vector(3072, float16);

    -- Compute the query embedding (keep your model name as-is)
    -- If you prefer to handle errors, wrap in TRY/CATCH and bail if @vector is NULL.
    SELECT @vector = AI_GENERATE_EMBEDDINGS(@prompt USE MODEL MyAzureOpenAIModel);

    IF @vector IS NULL RETURN;

    ;WITH exact_nn AS
    (
        SELECT TOP (@top)
            p.Name                              AS ProductName,
            pd.Description                      AS ProductDescription,
            p.SafetyStockLevel                  AS StockLevel,
            d.distance                          AS distance,                 -- cosine distance [0..2]
            CAST(1.0 - d.distance AS decimal(19,16)) AS similarity           -- cosine similarity [-1..1]
        FROM Production.ProductDescriptionEmbeddings AS pe
        CROSS APPLY (SELECT VECTOR_DISTANCE('cosine', pe.Embedding, @vector) AS distance) AS d
        JOIN Production.Product            AS p  ON p.ProductID = pe.ProductID
        JOIN Production.ProductDescription AS pd ON pd.ProductDescriptionID = pe.ProductDescriptionID
        WHERE p.SafetyStockLevel >= @stock
        ORDER BY d.distance ASC  -- exact k-NN by true distance
    )
    SELECT
        ProductName,
        ProductDescription,
        StockLevel
    FROM exact_nn
    WHERE similarity >= @min_similarity
    ORDER BY distance ASC;
END
GO

-- Give it a spin
EXEC find_relevant_products_vector_precise
@prompt = N'I want a gliding, pillow‑y feel on battered streets, zero buzz through the hands.',
@stock = 100, 
@top = 20
GO
