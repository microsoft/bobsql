USE AdventureWorks;
GO
-- Create a new table to store embeddings
--
DROP TABLE IF EXISTS Production.ProductDescriptionEmbeddings;
GO
CREATE TABLE Production.ProductDescriptionEmbeddings
( 
  ProductDescEmbeddingID INT IDENTITY NOT NULL PRIMARY KEY CLUSTERED,
  ProductID INT NOT NULL,
  ProductDescriptionID INT NOT NULL,
  ProductModelID INT NOT NULL,
  CultureID nchar(6) NOT NULL,
  Embedding vector(1536)
);