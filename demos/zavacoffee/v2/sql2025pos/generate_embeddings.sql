USE [zavapos];
GO
INSERT INTO edge.product_embeddings
SELECT p.product_id, AI_GENERATE_EMBEDDINGS (p.product_desc USE MODEL MyLocalEmbeddingModel)
FROM edge.product p;
GO