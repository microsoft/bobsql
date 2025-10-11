USE [zavapos];
GO

CREATE OR ALTER PROCEDURE edge.usp_SearchProducts_ByPrompt_ANN
    @prompt            NVARCHAR(MAX),
    @type              NVARCHAR(50) = NULL,    -- JSON $.type (e.g., 'beverage','food','retail','merch')
    @subtype           NVARCHAR(50) = NULL,    -- JSON $.subtype (e.g., 'latte','espresso','cold_brew',...)
    @serve             NVARCHAR(10) = NULL,    -- JSON $.serve ('hot'|'cold')
    @store_id          INT          = NULL,    -- optional scope to a store
    @topK              INT          = 10,      -- final rows to return
    @min_similarity decimal(19,16) = 0.3
AS
BEGIN
    SET NOCOUNT ON;

    /* ---- Validate inputs ---- */
    IF @prompt IS NULL OR LTRIM(RTRIM(@prompt)) = ''
    BEGIN
        RAISERROR('Prompt cannot be empty.', 16, 1);
        RETURN;
    END;

    /* ---- 1) Create query embedding ---- */
    DECLARE @qv VECTOR(1024);

    SELECT @qv = AI_GENERATE_EMBEDDINGS(@prompt USE MODEL MyLocalEmbeddingModel);
    -- If your build exposes AI_GENERATE_EMBEDDING (singular), swap it in.

    IF @qv IS NULL
    BEGIN
        RAISERROR('Failed to generate embedding for the prompt.', 16, 1);
        RETURN;
    END;

     SELECT  pe.product_id,
             p.product_name,
             p.product_desc,
             pe.embeddings,
             r.distance                 -- distance comes from result alias
        FROM    VECTOR_SEARCH(
                    TABLE      = edge.product_embeddings AS pe,  -- source-table alias
                    COLUMN     = embeddings,
                    SIMILAR_TO = @qv,
                    METRIC     = 'cosine',                       -- hardcoded metric
                    TOP_N      = @topK
                ) AS r
    JOIN edge.Product p
    ON p.product_id = pe.product_id
    WHERE (1-r.distance) > @min_similarity
    AND @type = JSON_VALUE(p.product_attribute, '$.type')
    ORDER BY r.distance;                                     
END
