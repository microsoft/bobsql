USE AdventureWorks;
GO
-- Create a new table to store embeddings
--
DROP TABLE IF EXISTS Production.ProductDescriptionEmbeddings;
GO
CREATE TABLE Production.ProductDescriptionEmbeddings
( 
  Embedding vector(768),
  ProductDescEmbeddingID INT IDENTITY NOT NULL PRIMARY KEY CLUSTERED,
  ProductID INT NOT NULL,
  ProductDescriptionID INT NOT NULL,
  ProductModelID INT NOT NULL
 );
GO

-- Populate rows with embeddings
-- Need to make sure and only get Products that have ProductModels
INSERT INTO Production.ProductDescriptionEmbeddings
SELECT AI_GENERATE_EMBEDDINGS(pd.Description USE MODEL MyOpenAIModel), p.ProductID, pmpdc.ProductDescriptionID, pmpdc.ProductModelID--, --pmpdc.CultureID, 
FROM Production.ProductModelProductDescriptionCulture pmpdc
JOIN Production.Product p
ON pmpdc.ProductModelID = p.ProductModelID
AND pmpdc.CultureID IN ('en', 'fr')
JOIN Production.ProductDescription pd
ON pd.ProductDescriptionID = pmpdc.ProductDescriptionID
GO
-- Explore embeddings
SELECT p.ProductID, p.Name, pd.Description, pde.Embedding 
FROM Production.ProductDescriptionEmbeddings pde
JOIN Production.Product p
ON pde.ProductID = p.ProductID
JOIN Production.ProductDescription pd
ON pd.ProductDescriptionID = pde.ProductDescriptionID
GO