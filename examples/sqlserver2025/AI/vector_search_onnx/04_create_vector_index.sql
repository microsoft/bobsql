USE [AdventureWorks];
GO
CREATE VECTOR INDEX product_vector_index 
ON Production.ProductDescriptionEmbeddings (Embedding)
WITH (METRIC = 'cosine', TYPE = 'diskann', MAXDOP = 8);
GO
-- Vector index typically is only small fraction of overall table size
EXEC sp_spaceused 'Production.ProductDescriptionEmbeddings';
GO