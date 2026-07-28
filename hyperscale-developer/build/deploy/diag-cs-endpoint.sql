SET NOCOUNT ON;
/* Diagnostic: call gpt-5 DIRECTLY at the cognitiveservices.azure.com endpoint
   (the host APIM's backend points at), bypassing APIM, using the DB's own MI.
   If this 500s -> the endpoint/host is the problem, not APIM.
   If this 200s -> APIM is the problem. */
IF EXISTS (SELECT 1 FROM sys.database_scoped_credentials
           WHERE name = 'https://collierhealth-ai.cognitiveservices.azure.com/')
    DROP DATABASE SCOPED CREDENTIAL [https://collierhealth-ai.cognitiveservices.azure.com/];
GO
CREATE DATABASE SCOPED CREDENTIAL [https://collierhealth-ai.cognitiveservices.azure.com/]
WITH IDENTITY = 'Managed Identity',
     SECRET   = '{"resourceid":"https://cognitiveservices.azure.com"}';
GO
DECLARE @payload NVARCHAR(MAX) =
    N'{"messages":[{"role":"user","content":"Reply with the single word OK."}],"max_completion_tokens":50,"reasoning_effort":"low"}';
DECLARE @resp NVARCHAR(MAX), @ret INT;
DECLARE @url NVARCHAR(500) =
    N'https://collierhealth-ai.cognitiveservices.azure.com/openai/deployments/gpt-5/chat/completions?api-version=2025-04-01-preview';
EXEC @ret = sp_invoke_external_rest_endpoint
    @url = @url, @method = 'POST',
    @credential = [https://collierhealth-ai.cognitiveservices.azure.com/],
    @payload = @payload, @timeout = 120, @response = @resp OUTPUT;
SELECT CONCAT('cs_endpoint_ret=', @ret, ' resp=', LEFT(@resp, 400)) AS x;
GO
