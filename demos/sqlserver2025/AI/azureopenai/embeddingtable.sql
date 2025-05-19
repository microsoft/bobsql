USE AdventureWorks;
GO
-- Create a new table to store embeddings
--
DROP TABLE IF EXISTS Production.ProductDescriptionEmbeddings;
GO
CREATE TABLE Production.ProductDescriptionEmbeddings
( 
  ProductDescEmbeddingID INT IDENTITY NOT NULL PRIMARY KEY CLUSTERED, -- Need a single column as cl index to support vector index reqs
  ProductID INT NOT NULL,
  ProductDescriptionID INT NOT NULL,
  ProductModelID INT NOT NULL,
  CultureID nchar(6) NOT NULL,
  Embedding vector(1536)
);

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

-- Create an alternate key using an ncl index
CREATE UNIQUE NONCLUSTERED INDEX [IX_ProductDescriptionEmbeddings_AlternateKey]
ON [Production].[ProductDescriptionEmbeddings]
(
    [ProductID] ASC,
    [ProductModelID] ASC,
    [ProductDescriptionID] ASC,
    [CultureID] ASC
);
GO




