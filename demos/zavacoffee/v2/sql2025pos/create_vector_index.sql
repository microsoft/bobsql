USE [zavapos];
GO
CREATE VECTOR INDEX product_vector_index 
ON edge.product_embeddings (embeddings)
WITH (METRIC = 'cosine', TYPE = 'diskann', MAXDOP = 8);
GO