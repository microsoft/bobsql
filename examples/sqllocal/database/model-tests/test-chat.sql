USE CaldovaFoundryModelTests;
GO
SET NOCOUNT ON;

DECLARE @Credential sysname = N'https://192.0.2.10/gpt-oss-20b';
DECLARE @Prompt nvarchar(2000) = N'Reply with exactly: Caldova SQL HTTPS is working.';
DECLARE @ShowFullResponse bit = 0;

IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = @Credential)
    THROW 50000, 'Run setup/Initialize-FoundrySqlTests.ps1 to configure the isolated test credentials.', 1;

DECLARE @Payload nvarchar(max) =
    N'{"model":"gpt-oss-20b","messages":[{"role":"user","content":"' +
    STRING_ESCAPE(@Prompt, 'json') + N'"}],"max_tokens":256,"temperature":0}';
DECLARE @Response nvarchar(max);
DECLARE @ReturnCode int;
DECLARE @StartedAt datetime2(3) = SYSUTCDATETIME();

BEGIN TRY
    EXEC @ReturnCode = sys.sp_invoke_external_rest_endpoint
        @url = N'https://192.0.2.10/gpt-oss-20b/v1/chat/completions',
        @method = N'POST',
        @headers = N'{"Content-Type":"application/json"}',
        @credential = @Credential,
        @payload = @Payload,
        @timeout = 180,
        @response = @Response OUTPUT;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage, @Response AS FullResponse;
    THROW;
END CATCH;

DECLARE @LatencyMs int = DATEDIFF(MILLISECOND, @StartedAt, SYSUTCDATETIME());
IF @Response IS NULL OR ISJSON(@Response) <> 1
BEGIN
    SELECT @ReturnCode AS ReturnCode, @Response AS FullResponse;
    THROW 50000, 'SQL REST invocation did not return a JSON response.', 1;
END;
DECLARE @HttpStatus int = TRY_CONVERT(int, JSON_VALUE(@Response, '$.response.status.http.code'));
IF @ReturnCode IS NULL OR @ReturnCode <> 0 OR @HttpStatus IS NULL OR @HttpStatus <> 200
BEGIN
    SELECT @ReturnCode AS ReturnCode, @HttpStatus AS HttpStatusCode, @Response AS FullResponse;
    THROW 50000, 'The chat endpoint did not return HTTP 200 through SQL Server.', 1;
END;

DECLARE @ModelResponse nvarchar(max);
DECLARE @FinishReason nvarchar(30);
SELECT @ModelResponse = ModelResponse, @FinishReason = FinishReason
FROM OPENJSON(@Response, '$.result.choices')
WITH (
    ModelResponse nvarchar(max) '$.message.content',
    FinishReason nvarchar(30) '$.finish_reason'
);
IF (SELECT COUNT(*) FROM OPENJSON(@Response, '$.result.choices')) <> 1
    OR NULLIF(LTRIM(RTRIM(@ModelResponse)), N'') IS NULL
BEGIN
    SELECT @Response AS FullResponse;
    THROW 50000, 'Chat response must contain one nonempty assistant message.', 1;
END;

SELECT
    @Prompt AS Prompt,
    @ReturnCode AS ReturnCode,
    @HttpStatus AS HttpStatusCode,
    @LatencyMs AS LatencyMs,
    JSON_VALUE(@Response, '$.result.model') AS ModelId,
    @FinishReason AS FinishReason,
    @ModelResponse AS ModelResponse;

IF @ShowFullResponse = 1
    SELECT @Response AS FullResponse;
GO
