USE AdventureWorks;
GO

-- STEP 1: Store the results of vector search in a temp table
DROP TABLE IF EXISTS #ProcResult;
CREATE TABLE #ProcResult
(
    ProductName         NVARCHAR(200)  NULL,
    ProductDescription  NVARCHAR(MAX)  NULL,
    StockLevel          INT            NULL
);
INSERT INTO #ProcResult (ProductName, ProductDescription, StockLevel)
EXEC find_relevant_products_vector_search
@prompt = N'Show me stuff for extreme outdoor sports',
@stock = 100, 
@top = 20;

-- STEP 2: Convert the result set to JSON
DECLARE @resultSetJson NVARCHAR(MAX);
SELECT @resultSetJson =
(
    SELECT ProductName, ProductDescription
    FROM #ProcResult
    FOR JSON PATH, INCLUDE_NULL_VALUES
);

-- STEP 3: Build Chat Completions parameters
DECLARE @escapedJson   NVARCHAR(MAX) = STRING_ESCAPE(@resultSetJson, 'json');
DECLARE @url NVARCHAR(MAX) = N'https://<azureai>.openai.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2025-01-01-preview';
DECLARE @credential NVARCHAR(4000)  = N'https://<azureai>.openai.azure.com';  -- DB scoped credential name
DECLARE @headers    NVARCHAR(MAX)   = N'{"Content-Type":"application/json"}';
DECLARE @userPrompt NVARCHAR(MAX)   = N'Are these good products for someone who is an extreme sports enthusiast. Anything missing?';
DECLARE @payload NVARCHAR(MAX);
SET @payload = 
N'{
  "messages": [
    { "role": "system", "content": "You are a helpful assistant that analyzes small SQL result sets about products from an outdoor sports company. Be concise, structured, and actionable." },
    { "role": "user",   "content": "'+@userPrompt +'"},
    { "role": "user",   "content": "'+@escapedJson+ '"}
  ],
  "temperature": 0.7
}';

-- STEP 4: Execute the chat completion
DECLARE @statusCode INT;
DECLARE @response NVARCHAR(MAX);
EXEC @statusCode = sp_invoke_external_rest_endpoint
    @url        = @url,
    @method     = N'POST',
    @headers    = @headers,
    @payload    = @payload,
    @credential = @credential,
    @response = @response OUTPUT,
    @timeout    = 120;


-- STEP 5: Extract out the response message
SELECT c.content
FROM OPENJSON(@response, '$.result.choices')
WITH ( content NVARCHAR(MAX) '$.message.content' ) AS c;
GO