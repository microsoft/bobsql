-- Create vector index
USE zavacliniq;
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE VECTOR INDEX chunk_vector_index
ON content.ChunkEmbedding(Embedding)
WITH (METRIC = 'cosine', TYPE = 'diskann', MAXDOP = 8);
GO