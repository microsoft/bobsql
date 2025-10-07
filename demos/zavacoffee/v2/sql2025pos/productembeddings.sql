USE zavapos;
GO
-- Product embedding table
DROP TABLE IF EXISTS edge.Product_Embeddings;
GO
CREATE TABLE edge.Product_Embeddings(
    product_id BIGINT NOT NULL,
    product_embeddings vector(1536) NOT NULL
);
GO