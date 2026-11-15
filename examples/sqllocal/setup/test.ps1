[CmdletBinding()]
param(
    [string]$KubeconfigPath = (Join-Path $PSScriptRoot 'caldova-admin.kubeconfig'),
    [string]$ServerInstance = 'localhost',
    [string]$Database = 'tempdb',
    [string]$DeploymentName = 'phi-35-mini',
    [string]$FoundryNamespace = 'foundry-local-operator',
    [string]$ExternalIPAddress = '192.0.2.10',
    [ValidateLength(1, 2000)]
    [string]$Prompt = 'Reply in one short sentence confirming SQL Server reached Foundry Local directly through the external AKS Arc Gateway.'
)

$ErrorActionPreference = 'Stop'
$credentialUrl = "https://$ExternalIPAddress/$DeploymentName"
$chatUrl = "$credentialUrl/v1/chat/completions"

foreach ($commandName in 'kubectl', 'curl.exe') {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "Required command '$commandName' was not found."
    }
}

$parsedAddress = $null
if (-not [Net.IPAddress]::TryParse($ExternalIPAddress, [ref]$parsedAddress)) {
    throw "ExternalIPAddress '$ExternalIPAddress' is not a valid IP address."
}

function New-SqlConnection {
    param([Parameter(Mandatory)][string]$InitialCatalog)

    $builder = [Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = $ServerInstance
    $builder['Initial Catalog'] = $InitialCatalog
    $builder['Integrated Security'] = $true
    $builder['Encrypt'] = $true
    $builder['TrustServerCertificate'] = $true
    $builder['Application Name'] = 'Foundry Local direct IP SQL demo'
    return [Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
}

function Invoke-SqlNonQuery {
    param(
        [Parameter(Mandatory)][Data.SqlClient.SqlConnection]$Connection,
        [Parameter(Mandatory)][string]$CommandText,
        [hashtable]$Parameters = @{},
        [int]$CommandTimeout = 30
    )

    $command = $Connection.CreateCommand()
    try {
        $command.CommandText = $CommandText
        $command.CommandTimeout = $CommandTimeout
        foreach ($parameterName in $Parameters.Keys) {
            [void]$command.Parameters.AddWithValue($parameterName, $Parameters[$parameterName])
        }
        [void]$command.ExecuteNonQuery()
    }
    finally {
        $command.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $KubeconfigPath -PathType Leaf)) {
    throw "The admin kubeconfig was not found at '$KubeconfigPath'."
}

Write-Host 'Checking direct Kubernetes access...'
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
try {
    $namespace = & kubectl `
        --kubeconfig $KubeconfigPath `
        get namespace $FoundryNamespace `
        --output name `
        --request-timeout=15s 2>$null
    $namespaceExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousPreference
}
if ($namespaceExitCode -ne 0 -or $namespace -ne "namespace/$FoundryNamespace") {
    throw "The Kubernetes API is unavailable through '$KubeconfigPath'."
}

Write-Host "Checking ModelDeployment '$DeploymentName'..."
$deploymentJson = & kubectl `
    --kubeconfig $KubeconfigPath `
    get modeldeployments.foundrylocal.azure.com $DeploymentName `
    --namespace $FoundryNamespace `
    --request-timeout=15s `
    --output json
if ($LASTEXITCODE -ne 0 -or -not $deploymentJson) {
    throw "Unable to read ModelDeployment '$DeploymentName'."
}
$deployment = $deploymentJson | ConvertFrom-Json
if ($deployment.status.state -ne 'Running' -or $deployment.status.deploymentReady -ne $true) {
    throw "ModelDeployment '$DeploymentName' is not running and ready."
}
$modelId = '{0}:{1}' -f (
    $deployment.spec.model.catalog.name,
    $deployment.spec.model.catalog.version
)

Write-Host 'Retrieving the model API key...'
$encodedApiKey = & kubectl `
    --kubeconfig $KubeconfigPath `
    get secret "$DeploymentName-api-keys" `
    --namespace $FoundryNamespace `
    --request-timeout=15s `
    --output 'jsonpath={.data.primary-key}'
if ($LASTEXITCODE -ne 0 -or -not $encodedApiKey) {
    throw "Unable to retrieve the primary API key for '$DeploymentName'."
}
$apiKey = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedApiKey))
if ([string]::IsNullOrWhiteSpace($apiKey) -or $apiKey -match '[\r\n]') {
    throw "The primary API key for '$DeploymentName' is empty or contains line breaks."
}

$escapedApiKey = $apiKey.Replace('\', '\\').Replace('"', '\"')
$curlConfig = 'header = "api-key: {0}"' -f $escapedApiKey
Write-Host "Testing trusted HTTPS directly at '$credentialUrl'..."
$curlConfig | & curl.exe `
    --config - `
    --silent `
    --show-error `
    --fail-with-body `
    --ssl-revoke-best-effort `
    --connect-timeout 10 `
    --max-time 30 `
    "$credentialUrl/v1/model" | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Trusted HTTPS validation failed. Confirm the lab root is in LocalMachine\Root and the Gateway presents the IP-SAN certificate.'
}
Write-Host 'Trusted direct-IP HTTPS validation passed without --insecure.' -ForegroundColor Green

$masterConnection = New-SqlConnection -InitialCatalog 'master'
$databaseConnection = $null
try {
    Write-Host "Connecting to SQL Server '$ServerInstance'..."
    $masterConnection.Open()
    Write-Host 'Enabling SQL Server external REST endpoint access...'
    Invoke-SqlNonQuery `
        -Connection $masterConnection `
        -CommandText @'
EXEC sys.sp_configure N'external rest endpoint enabled', 1;
RECONFIGURE WITH OVERRIDE;
'@

    Write-Host "Configuring temporary objects in '$Database'..."
    $databaseConnection = New-SqlConnection -InitialCatalog $Database
    $databaseConnection.Open()

    $masterKeyBytes = [byte[]]::new(48)
    $randomNumberGenerator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $randomNumberGenerator.GetBytes($masterKeyBytes)
    }
    finally {
        $randomNumberGenerator.Dispose()
    }
    $masterKeyPassword = [Convert]::ToBase64String($masterKeyBytes) + '!aA1'
    Invoke-SqlNonQuery `
        -Connection $databaseConnection `
        -CommandText @'
IF NOT EXISTS (
    SELECT 1
    FROM sys.symmetric_keys
    WHERE [name] = N'##MS_DatabaseMasterKey##'
)
BEGIN
    DECLARE @CreateMasterKeySql NVARCHAR(MAX) =
        N'CREATE MASTER KEY ENCRYPTION BY PASSWORD = N''' +
        REPLACE(@MasterKeyPassword, N'''', N'''''') + N''';';
    EXEC sys.sp_executesql @CreateMasterKeySql;
END;
'@ `
        -Parameters @{ '@MasterKeyPassword' = $masterKeyPassword }

    $escapedCredentialUrl = $credentialUrl.Replace("'", "''")
    $credentialProcedureSql = @"
CREATE OR ALTER PROCEDURE dbo.usp_ConfigureFoundryLocalDirectIpCredential
    @ApiKey NVARCHAR(4000)
AS
BEGIN
    SET NOCOUNT ON;

    IF NULLIF(@ApiKey, N'') IS NULL
        THROW 50000, 'The Foundry Local API key is required.', 1;

    DECLARE @CredentialName SYSNAME = N'$escapedCredentialUrl';
    DECLARE @Secret NVARCHAR(MAX) =
        N'{"api-key":"' + STRING_ESCAPE(@ApiKey, 'json') + N'"}';
    DECLARE @Sql NVARCHAR(MAX) =
        N'IF EXISTS (
              SELECT 1 FROM sys.database_scoped_credentials
              WHERE [name] = N''' +
                  REPLACE(@CredentialName, N'''', N'''''') + N'''
          )
              DROP DATABASE SCOPED CREDENTIAL ' +
                  QUOTENAME(@CredentialName) + N';
          CREATE DATABASE SCOPED CREDENTIAL ' +
              QUOTENAME(@CredentialName) + N'
          WITH IDENTITY = ''HTTPEndpointHeaders'',
               SECRET = N''' + REPLACE(@Secret, N'''', N'''''') + N''';';

    EXEC sys.sp_executesql @Sql;
END;
"@
    Invoke-SqlNonQuery -Connection $databaseConnection -CommandText $credentialProcedureSql

    $credentialCommand = $databaseConnection.CreateCommand()
    try {
        $credentialCommand.CommandType = [Data.CommandType]::StoredProcedure
        $credentialCommand.CommandText = 'dbo.usp_ConfigureFoundryLocalDirectIpCredential'
        $apiKeyParameter = $credentialCommand.Parameters.Add('@ApiKey', [Data.SqlDbType]::NVarChar, 4000)
        $apiKeyParameter.Value = $apiKey
        [void]$credentialCommand.ExecuteNonQuery()
    }
    finally {
        $credentialCommand.Dispose()
    }

    $escapedModelId = $modelId.Replace("'", "''")
    $chatProcedureSql = @"
CREATE OR ALTER PROCEDURE dbo.usp_TestFoundryLocalDirectIpChat
    @Prompt NVARCHAR(2000)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Payload NVARCHAR(MAX) =
        N'{"model":"$escapedModelId","messages":[{"role":"user","content":"' +
        STRING_ESCAPE(@Prompt, 'json') +
        N'"}],"max_tokens":120,"temperature":0}';
    DECLARE @Response NVARCHAR(MAX);
    DECLARE @ReturnCode INT;
    DECLARE @StartedAt DATETIME2(3) = SYSUTCDATETIME();

    EXEC @ReturnCode = sys.sp_invoke_external_rest_endpoint
        @url = N'$chatUrl',
        @method = N'POST',
        @credential = [$credentialUrl],
        @payload = @Payload,
        @timeout = 120,
        @response = @Response OUTPUT;

    SELECT
        @Prompt AS Prompt,
        @ReturnCode AS ReturnCode,
        JSON_VALUE(@Response, '$.response.status.http.code') AS HttpStatusCode,
        DATEDIFF(MILLISECOND, @StartedAt, SYSUTCDATETIME()) AS LatencyMs,
        JSON_VALUE(@Response, '$.result.model') AS ModelId,
        JSON_VALUE(@Response, '$.result.choices[0].message.content') AS ModelResponse,
        CASE WHEN @ReturnCode = 0 THEN NULL ELSE @Response END AS ErrorResponse;
END;
"@
    Invoke-SqlNonQuery -Connection $databaseConnection -CommandText $chatProcedureSql

    $chatCommand = $databaseConnection.CreateCommand()
    try {
        $chatCommand.CommandType = [Data.CommandType]::StoredProcedure
        $chatCommand.CommandText = 'dbo.usp_TestFoundryLocalDirectIpChat'
        $chatCommand.CommandTimeout = 150
        $promptParameter = $chatCommand.Parameters.Add('@Prompt', [Data.SqlDbType]::NVarChar, 2000)
        $promptParameter.Value = $Prompt

        Write-Host 'Invoking the model through SQL Server; this can take up to 120 seconds...'
        $reader = $chatCommand.ExecuteReader()
        try {
            if (-not $reader.Read()) {
                throw 'The direct-IP chat procedure returned no result row.'
            }
            $result = [pscustomobject]@{
                Prompt        = $reader['Prompt']
                ReturnCode    = $reader['ReturnCode']
                HttpStatus    = $reader['HttpStatusCode']
                LatencyMs     = $reader['LatencyMs']
                ModelId       = $reader['ModelId']
                ModelResponse = $reader['ModelResponse']
                ErrorResponse = $reader['ErrorResponse']
            }
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $chatCommand.Dispose()
    }

    Write-Host ''
    Write-Host 'Prompt:' -ForegroundColor Cyan
    Write-Host $result.Prompt
    Write-Host ''
    Write-Host 'Model response:' -ForegroundColor Cyan
    Write-Host $result.ModelResponse
    Write-Host ''
    Write-Host "Return code: $($result.ReturnCode)"
    Write-Host "HTTP status: $($result.HttpStatus)"
    Write-Host "Latency:     $($result.LatencyMs) ms"
    Write-Host "Model:       $($result.ModelId)"

    if ($result.ReturnCode -ne 0) {
        throw "Foundry Local returned an error: $($result.ErrorResponse)"
    }
    Write-Host 'SQL Server reached Foundry Local directly through the external Gateway.' -ForegroundColor Green
}
finally {
    if ($databaseConnection) {
        $databaseConnection.Dispose()
    }
    $masterConnection.Dispose()
    $apiKey = $null
    $encodedApiKey = $null
    $masterKeyPassword = $null
    $masterKeyBytes = $null
}