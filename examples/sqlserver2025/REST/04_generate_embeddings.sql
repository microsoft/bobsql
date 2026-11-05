/* Generate embeddings */
USE zavacliniq;
GO
INSERT INTO content.ChunkEmbedding
SELECT c.ChunkId, AI_GENERATE_EMBEDDINGS (c.ChunkText USE MODEL MyOllamaEmbeddingModel)
FROM content.Chunk c
GO