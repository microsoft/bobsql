USE [AdventureWorks];
GO

CREATE OR ALTER PROCEDURE [find_relevant_products_vector_search]
@prompt NVARCHAR(max), -- NL prompt
@stock SMALLINT = 500, -- Only show product with stock level of >= 500. User can override
@top INT = 10, -- Only show top 10. User can override
@min_similarity DECIMAL(19,16) = 0.3 -- Similarity level that user can change but recommend to leave default
AS
IF (@prompt is null) RETURN;

DECLARE @retval INT, @vector VECTOR(1536);

SELECT @vector = AI_GENERATE_EMBEDDINGS(@prompt USE MODEL MyAzureOpenAIEmbeddingModel)

IF (@retval != 0) RETURN;

SELECT p.Name as ProductName, pd.Description AS ProductDescription, p.SafetyStockLevel AS StockLevel
FROM vector_search(
	TABLE = Production.ProductDescriptionEmbeddings AS t,
	COLUMN = Embedding,
	similar_to = @vector,
	metric = 'cosine',
	top_n = @top
	) AS s
JOIN Production.ProductDescriptionEmbeddings pe
ON t.ProductDescEmbeddingID = pe.ProductDescEmbeddingID
JOIN Production.Product p
ON pe.ProductID = p.ProductID
JOIN Production.ProductDescription pd
ON pd.ProductDescriptionID = pe.ProductDescriptionID
WHERE (1-s.distance) > @min_similarity
AND p.SafetyStockLevel >= @stock
ORDER by s.distance;
GO
