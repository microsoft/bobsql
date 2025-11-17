USE [AdventureWorks];
GO

CREATE OR ALTER procedure [find_relevant_products_vector_search]
@prompt nvarchar(max), -- NL prompt
@stock smallint = 500, -- Only show product with stock level of >= 500. User can override
@top int = 10, -- Only show top 10. User can override
@min_similarity decimal(19,16) = 0.3 -- Similarity level that user can change but recommend to leave default
AS
IF (@prompt is null) RETURN;

DECLARE @retval int, @vector vector(384);

SELECT @vector = AI_GENERATE_EMBEDDINGS(@prompt USE MODEL MyLocalONNXModel);

IF (@retval != 0) RETURN;

SELECT p.Name as ProductName, pd.Description as ProductDescription, p.SafetyStockLevel as StockLevel
FROM vector_search(
	table = Production.ProductDescriptionEmbeddings as t,
	column = Embedding,
	similar_to = @vector,
	metric = 'cosine',
	top_n = @top
	) as s
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

-- Give it a spin
EXEC find_relevant_products_vector_search
@prompt = N'I want a gliding, pillow‑y feel on battered streets, zero buzz through the hands.',
@stock = 100,
@top = 10
GO

-- Give it a spin
EXEC find_relevant_products_vector_search
@prompt = N'Je veux une impression de douceur et de confort, même quand la route est pourrie, sans que ça vibre dans les mains',
@stock = 100,
@top = 10
GO



