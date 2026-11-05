USE AdventureWorks;
GO
-- Populate rows with embeddings
-- Need to make sure and only get Products that have ProductModels
INSERT INTO Production.ProductDescriptionEmbeddings
SELECT p.ProductID, pmpdc.ProductDescriptionID, pmpdc.ProductModelID, pmpdc.CultureID, 

AI_GENERATE_EMBEDDINGS(pd.Description USE MODEL MyAzureOpenAIEmbeddingModel)

FROM Production.ProductModelProductDescriptionCulture pmpdc
JOIN Production.Product p
ON pmpdc.ProductModelID = p.ProductModelID
JOIN Production.ProductDescription pd
ON pd.ProductDescriptionID = pmpdc.ProductDescriptionID
ORDER BY p.ProductID;
GO


