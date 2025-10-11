USE [zavapos];
GO

CREATE OR ALTER PROCEDURE edge.usp_SearchProducts_ByPrompt
    @prompt        NVARCHAR(MAX),
    @type          NVARCHAR(50) = NULL,      -- e.g. 'beverage', 'food', 'retail', 'merch'
    @topK          INT          = 10,        -- number of results to return
    @metric        VARCHAR(20)  = 'cosine'   -- 'cosine' | 'euclidean' | 'dot'
AS
BEGIN
    SET NOCOUNT ON;

    IF @prompt IS NULL OR LTRIM(RTRIM(@prompt)) = ''
    BEGIN
        RAISERROR('Prompt cannot be empty.', 16, 1);
        RETURN;
    END;

    /* 1) Generate query embedding from the prompt using your EXTERNAL MODEL */
    DECLARE @qv VECTOR(768);

    SELECT @qv = AI_GENERATE_EMBEDDINGS(@prompt USE MODEL MyLocalEmbeddingModel);                                                                       └─ [1](https://www.red-gate.com/simple-talk/featured/using-regex-in-sql-server-2025-complete-guide/)

    IF @qv IS NULL
    BEGIN
        RAISERROR('Failed to generate embedding for the prompt.', 16, 1);
        RETURN;
    END;

    /* 2) Candidate set with optional JSON type filter */
    ;WITH candidates AS
    (
        SELECT  p.product_id,
                p.product_sku,
                p.product_name,
                p.product_desc,
                p.product_attribute,          -- native JSON
                p.list_price,
                pe.embeddings
        FROM    edge.product_Embeddings AS pe
        JOIN    edge.product            AS p
                ON p.product_id = pe.product_id
        WHERE   p.is_active = 1
          AND  (@type IS NULL OR JSON_VALUE(p.product_attribute, '$.type') = @type)
        -- JSON_VALUE on native JSON is supported in SQL Server 2025 preview.        [3](http://peter.eisentraut.org/blog/2025/06/24/waiting-for-sql-202y-vectors)
    ),
    scored AS
    (
        SELECT TOP (@topK)
               c.product_id,
               c.product_sku,
               c.product_name,
               c.product_desc,
               c.list_price,
               JSON_VALUE(c.product_attribute, '$.type')    AS type,
               JSON_VALUE(c.product_attribute, '$.subtype') AS subtype,

               /* Exact distance (no vector index) */
               VECTOR_DISTANCE(@metric, @qv, c.embeddings)  AS distance,

               /* Optional similarity (cosine only): 1 - distance */
               CASE WHEN @metric = 'cosine'
                    THEN (1.0 - VECTOR_DISTANCE('cosine', @qv, c.embeddings))
                    ELSE NULL
               END AS similarity
        FROM   candidates AS c
        ORDER BY distance ASC
    )
    SELECT *
    FROM   scored
    ORDER BY distance ASC;
END
GO