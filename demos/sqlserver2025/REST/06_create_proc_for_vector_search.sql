USE [zavacliniq];
GO

CREATE OR ALTER PROCEDURE content.SearchChunksByPrompt_Vector
    @Prompt              NVARCHAR(MAX),
    @TopK                INT            = 3,
    @min_similarity      FLOAT          = 0.3
AS
BEGIN
    SET NOCOUNT ON;

    IF @Prompt IS NULL OR LEN(@Prompt) = 0
    BEGIN
        RAISERROR('Prompt cannot be NULL or empty.', 16, 1);
        RETURN;
    END;

   -------------------------------------------------------------
    -- 1) Generate the query embedding
    -- NOTE: USE MODEL must be a literal identifier; bracket if needed.
    -------------------------------------------------------------
    DECLARE @QueryEmbedding VECTOR(1024);

    SELECT @QueryEmbedding =
        AI_GENERATE_EMBEDDINGS(
            @Prompt
             USE MODEL MyOllamaEmbeddingModel   -- <== your EXTERNAL MODEL name (quoted)
        );

    IF @QueryEmbedding IS NULL
    BEGIN
        RAISERROR('AI_GENERATE_EMBEDDINGS returned NULL. Verify EXTERNAL MODEL, permissions, endpoint.', 16, 1);
        RETURN;
    END;

    SELECT d.Title, d.DocType, c.ChunkText, s.distance
    FROM vector_search(
	table = content.ChunkEmbedding as ce,
	column = Embedding,
	similar_to = @QueryEmbedding,
	metric = 'cosine',
	top_n = @TopK
	) as s
    JOIN content.Chunk c
    ON ce.ChunkId = c.ChunkId
    JOIN content.Document d
    ON c.DocumentId = d.DocumentId
    AND d.isActive = 1
    WHERE (1-s.distance) > @min_similarity
    ORDER by s.distance;
END;
GO