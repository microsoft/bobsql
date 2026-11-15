USE CaldovaFoundryModelTests;
GO
SET NOCOUNT ON;

DECLARE @Credential sysname = N'https://192.0.2.10/nemotron-3-embed-1b-bf16';
DECLARE @Input nvarchar(2000) = N'Synthetic transport note: patient reports shortness of breath.';
DECLARE @ExpectedDimensions int = 2048;
DECLARE @ShowFullResponse bit = 0;

IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = @Credential)
    THROW 50000, 'Run setup/Initialize-FoundrySqlTests.ps1 to configure the isolated test credentials.', 1;

DECLARE @Payload nvarchar(max) =
    N'{"model":"nemotron-3-embed-1b-bf16","input":["' +
    STRING_ESCAPE(@Input, 'json') + N'"],"encoding_format":"float"}';
DECLARE @Response nvarchar(max);
DECLARE @ReturnCode int;
DECLARE @StartedAt datetime2(3) = SYSUTCDATETIME();

BEGIN TRY
    EXEC @ReturnCode = sys.sp_invoke_external_rest_endpoint
        @url = N'https://192.0.2.10/nemotron-3-embed-1b-bf16/v1/embeddings',
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
    THROW 50000, 'The embedding endpoint did not return HTTP 200 through SQL Server.', 1;
END;

DECLARE @Embedding nvarchar(max) = JSON_QUERY(@Response, '$.result.data[0].embedding');
IF (SELECT COUNT(*) FROM OPENJSON(@Response, '$.result.data')) <> 1
    OR TRY_CONVERT(int, JSON_VALUE(@Response, '$.result.data[0].index')) IS NULL
    OR TRY_CONVERT(int, JSON_VALUE(@Response, '$.result.data[0].index')) <> 0
    OR @Embedding IS NULL OR LEFT(LTRIM(@Embedding), 1) <> N'['
BEGIN
    SELECT @Response AS FullResponse;
    THROW 50000, 'Expected one embedding array at result.data[0], with index 0.', 1;
END;

DECLARE @Dimensions int = (SELECT COUNT(*) FROM OPENJSON(@Embedding));
IF @Dimensions <> @ExpectedDimensions OR EXISTS (
    SELECT 1 FROM OPENJSON(@Embedding)
    WHERE type <> 2 OR TRY_CONVERT(float, value) IS NULL
)
BEGIN
    SELECT @Dimensions AS ActualDimensions, @ExpectedDimensions AS ExpectedDimensions, @Response AS FullResponse;
    THROW 50000, 'The embedding must contain exactly 2048 numeric dimensions.', 1;
END;

DECLARE @EmbeddingVector VECTOR(2048, float16) = CAST(@Embedding AS VECTOR(2048, float16));
DECLARE @StoredEmbedding nvarchar(max) = CAST(@EmbeddingVector AS nvarchar(max));
DECLARE @StoredDimensions int = (SELECT COUNT(*) FROM OPENJSON(@StoredEmbedding));
IF @StoredDimensions <> @ExpectedDimensions
    THROW 50000, 'Float16 conversion did not preserve all 2048 dimensions.', 1;

SELECT
    @Input AS InputText,
    @ReturnCode AS ReturnCode,
    @HttpStatus AS HttpStatusCode,
    @LatencyMs AS LatencyMs,
    JSON_VALUE(@Response, '$.result.model') AS ModelId,
    @StoredDimensions AS Dimensions,
    N'float16' AS VectorBaseType,
    DATALENGTH(@EmbeddingVector) AS VectorBytes,
    (SELECT TOP (8) CONVERT(int, [key]) AS Dimension, CONVERT(float, value) AS Value
     FROM OPENJSON(@StoredEmbedding)
     ORDER BY CONVERT(int, [key])
     FOR JSON PATH) AS FirstEightDimensions;

IF @ShowFullResponse = 1
    SELECT @Response AS FullResponse, @EmbeddingVector AS EmbeddingVector, @StoredEmbedding AS Float16VectorJson;
GO
