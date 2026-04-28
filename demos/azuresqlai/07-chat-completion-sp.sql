-- ============================================================================
-- 07-chat-completion-sp.sql
-- Creates a RAG (Retrieval Augmented Generation) stored procedure that:
--   1. Generates an embedding for the user's question
--   2. Performs vector search to find relevant context
--   3. Calls Azure OpenAI chat completion via sp_invoke_external_rest_endpoint
--   4. Returns the AI-generated answer grounded in your data
--
-- Uses managed identity for authentication (no API keys needed).
-- No SQLCMD mode required. The AOAI name is a parameter to the stored procedure.
-- ============================================================================

CREATE OR ALTER PROCEDURE dbo.usp_chat_with_data
    @user_question NVARCHAR(MAX),
    @aoai_name NVARCHAR(200) = N'aoai-sqlai-demo',
    @top_k INT = 5
AS
BEGIN
    SET NOCOUNT ON;

    -- Build endpoint URL and credential name from the AOAI resource name
    DECLARE @url NVARCHAR(500) = N'https://' + @aoai_name + N'.openai.azure.com/openai/deployments/gpt-4.1-mini/chat/completions?api-version=2024-06-01';
    DECLARE @credential_name NVARCHAR(500) = N'https://' + @aoai_name + N'.openai.azure.com/';

    -- Step 1: Generate embedding for the user's question
    DECLARE @qv VECTOR(1536) = AI_GENERATE_EMBEDDINGS(@user_question USE MODEL EmbeddingModel);

    -- Step 2: Find relevant context via approximate vector search
    CREATE TABLE #context (
        title NVARCHAR(200),
        category NVARCHAR(100),
        content NVARCHAR(MAX),
        distance FLOAT
    );

    INSERT INTO #context
    SELECT TOP(@top_k) WITH APPROXIMATE
        t.title,
        t.category,
        t.content,
        s.distance
    FROM VECTOR_SEARCH(
        TABLE = dbo.azure_sql_knowledge AS t,
        COLUMN = embedding,
        SIMILAR_TO = @qv,
        METRIC = 'cosine'
    ) AS s
    ORDER BY s.distance;

    -- Build context string from retrieved documents
    DECLARE @context NVARCHAR(MAX);
    SELECT @context = STRING_AGG(
        N'[' + category + N'] ' + title + NCHAR(10) + content,
        NCHAR(10) + NCHAR(10)
    ) FROM #context;

    -- Step 3: Build the chat completion payload with system and user prompts
    DECLARE @system_prompt NVARCHAR(MAX) = N'You are an expert Azure SQL Database technical assistant. Your role is to provide accurate, helpful, and concise answers about Azure SQL Database features, capabilities, and best practices.

Rules:
- Answer ONLY based on the context provided below. Do not use external knowledge.
- If the context does not contain enough information to answer the question, clearly state that the available documentation does not cover this topic.
- When referencing specific features, mention the feature name exactly as it appears in the context.
- Provide practical guidance when possible, including relevant T-SQL syntax or configuration steps.
- Keep answers focused and well-structured. Use bullet points for lists of features or steps.
- If multiple context passages are relevant, synthesize them into a coherent answer.';

    DECLARE @user_prompt NVARCHAR(MAX) = N'## Retrieved Context (from Azure SQL knowledge base):

' + ISNULL(@context, N'No relevant context found.') + N'

## User Question:
' + @user_question + N'

Please provide a comprehensive answer based on the context above.';

    DECLARE @payload NVARCHAR(MAX) = JSON_OBJECT(
        'messages': JSON_ARRAY(
            JSON_OBJECT('role': 'system', 'content': @system_prompt),
            JSON_OBJECT('role': 'user', 'content': @user_prompt)
        ),
        'temperature': 0.7,
        'max_tokens': 1000
    );

    -- Step 4: Call Azure OpenAI chat completion via sp_invoke_external_rest_endpoint
    DECLARE @response NVARCHAR(MAX);
    DECLARE @ret INT;

    EXEC @ret = sp_invoke_external_rest_endpoint
        @url = @url,
        @method = 'POST',
        @credential = @credential_name,
        @payload = @payload,
        @response = @response OUTPUT;

    -- Step 5: Return the results
    SELECT
        @user_question AS question,
        JSON_VALUE(@response, '$.result.choices[0].message.content') AS ai_response,
        JSON_VALUE(@response, '$.result.usage.prompt_tokens') AS prompt_tokens,
        JSON_VALUE(@response, '$.result.usage.completion_tokens') AS completion_tokens,
        @ret AS http_status;

    -- Also return the context documents that were used (for transparency)
    SELECT
        title,
        category,
        distance,
        LEFT(content, 200) + '...' AS content_preview
    FROM #context
    ORDER BY distance;

    DROP TABLE #context;
END
GO

-- ============================================================================
-- Test the RAG chat completion stored procedure
-- ============================================================================

-- Ask about security features
EXEC dbo.usp_chat_with_data
    @user_question = N'What security features does Azure SQL Database offer to protect sensitive data? Compare encryption and masking options.';
GO

-- Ask about AI capabilities
EXEC dbo.usp_chat_with_data
    @user_question = N'How can I build an AI-powered application using Azure SQL Database? What vector search and embedding capabilities are available?';
GO

-- Ask about high availability and disaster recovery
EXEC dbo.usp_chat_with_data
    @user_question = N'What are my options for ensuring high availability and disaster recovery with Azure SQL Database?';
GO

-- Ask about performance optimization
EXEC dbo.usp_chat_with_data
    @user_question = N'My queries are running slow. What automatic performance tuning features can help without changing my application code?';
GO
