[CmdletBinding()]
param(
    [switch]$InitializeDatabase,
    [switch]$ConfigureModelOnly,
    [switch]$TestFoundryAi,
    [string]$ServerInstance = 'localhost',
    [string]$KubeconfigPath = 'C:\setup\caldova-admin.kubeconfig',
    [ValidateLength(1, 63)]
    [ValidatePattern('^[a-z0-9]([-a-z0-9]*[a-z0-9])?$')]
    [string]$DeploymentName = 'gpt-oss-20b',
    [string]$FoundryNamespace = 'foundry-local-operator',
    [string]$ExternalIPAddress = '192.0.2.10'
)

$ErrorActionPreference = 'Stop'
$databaseName = 'CaldovaRegionalCare'
if ($ConfigureModelOnly -and ($InitializeDatabase -or $TestFoundryAi)) {
    throw '-ConfigureModelOnly cannot be combined with initialization or full AI testing.'
}
$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue

if (-not $sqlcmd -and -not $ConfigureModelOnly) {
    throw 'sqlcmd was not found. Install it from https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-download-install and reopen PowerShell.'
}

function Invoke-CaldovaSqlScript {
    param([Parameter(Mandatory)][string]$Name)

    $path = Join-Path $PSScriptRoot $Name
    Write-Host "Running $Name..." -ForegroundColor Cyan
    & $sqlcmd.Source -S $ServerInstance -d master -E -C -b -i $path
    if ($LASTEXITCODE -ne 0) {
        throw "Database script failed: $Name"
    }
}

function New-CaldovaSqlConnection {
    $builder = [Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = $ServerInstance
    $builder['Initial Catalog'] = $databaseName
    $builder['Integrated Security'] = $true
    $builder['Encrypt'] = $true
    $builder['TrustServerCertificate'] = $true
    $builder['Application Name'] = 'Caldova database setup'
    return [Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
}

function Invoke-SqlNonQuery {
    param(
        [Parameter(Mandatory)][Data.SqlClient.SqlConnection]$Connection,
        [Parameter(Mandatory)][string]$CommandText,
        [hashtable]$Parameters = @{}
    )

    $command = $Connection.CreateCommand()
    try {
        $command.CommandText = $CommandText
        foreach ($parameterName in $Parameters.Keys) {
            [void]$command.Parameters.AddWithValue($parameterName, $Parameters[$parameterName])
        }
        [void]$command.ExecuteNonQuery()
    }
    finally {
        $command.Dispose()
    }
}

function Set-AzureLocalGatewayEndpoint {
    foreach ($commandName in 'kubectl', 'curl.exe') {
        if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
            throw "Required command '$commandName' was not found. Run C:\setup\Setup.ps1 first."
        }
    }
    if (-not (Test-Path -LiteralPath $KubeconfigPath -PathType Leaf)) {
        throw "The admin kubeconfig was not found at '$KubeconfigPath'."
    }

    Write-Host "Reading ModelDeployment '$DeploymentName'..." -ForegroundColor Cyan
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
    $credentialUrl = "https://$ExternalIPAddress/$DeploymentName"
    $endpointName = "FoundryLocalOnAzureLocal-$DeploymentName"
    if ($credentialUrl.Length -gt 128 -or $endpointName.Length -gt 128) {
        throw 'The endpoint or credential name exceeds the SQL sysname limit.'
    }
    if ([string]::IsNullOrWhiteSpace($apiKey) -or $apiKey -match '[\r\n]') {
        throw 'The model API key is empty or contains invalid line breaks.'
    }
    $escapedApiKey = $apiKey.Replace('\', '\\').Replace('"', '\"')
    $curlConfig = 'header = "api-key: {0}"' -f $escapedApiKey

    Write-Host "Validating trusted HTTPS at '$credentialUrl'..." -ForegroundColor Cyan
    $modelListJson = $curlConfig | & curl.exe `
        --config - `
        --silent `
        --show-error `
        --fail-with-body `
        --ssl-revoke-best-effort `
        --connect-timeout 10 `
        --max-time 30 `
        "$credentialUrl/v1/models"
    if ($LASTEXITCODE -ne 0) {
        Write-Host ($modelListJson -join [Environment]::NewLine)
        throw 'Authenticated HTTPS model discovery failed. See the curl response above.'
    }
    $modelList = $modelListJson | ConvertFrom-Json
    $servedModels = @($modelList.data)
    if ($servedModels.Count -ne 1 -or [string]::IsNullOrWhiteSpace($servedModels[0].id)) {
        throw 'Expected exactly one served model with a nonempty ID at this deployment endpoint.'
    }
    $modelId = [string]$servedModels[0].id
    if ($modelId.Length -gt 256) {
        throw 'The served model ID exceeds the database column limit.'
    }

    $connection = New-CaldovaSqlConnection
    try {
        $connection.Open()

        $masterKeyBytes = [byte[]]::new(48)
        $randomNumberGenerator = [Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $randomNumberGenerator.GetBytes($masterKeyBytes)
        }
        finally {
            $randomNumberGenerator.Dispose()
        }
        $masterKeyPassword = [Convert]::ToBase64String($masterKeyBytes) + '!aA1'

        Invoke-SqlNonQuery -Connection $connection -CommandText @'
IF NOT EXISTS (
    SELECT 1 FROM sys.symmetric_keys
    WHERE [name] = N'##MS_DatabaseMasterKey##'
)
BEGIN
    DECLARE @Sql nvarchar(max) =
        N'CREATE MASTER KEY ENCRYPTION BY PASSWORD = N''' +
        REPLACE(@MasterKeyPassword, N'''', N'''''') + N''';';
    EXEC sys.sp_executesql @Sql;
END;
'@ -Parameters @{ '@MasterKeyPassword' = $masterKeyPassword }

        Invoke-SqlNonQuery -Connection $connection -CommandText @'
IF EXISTS (
    SELECT 1 FROM sys.database_scoped_credentials
    WHERE [name] = @CredentialUrl AND credential_identity <> N'HTTPEndpointHeaders'
)
    THROW 50000, 'Existing credential has an unexpected identity; it was not replaced.', 1;
DECLARE @Secret nvarchar(max) =
    N'{"api-key":"' + STRING_ESCAPE(@ApiKey, 'json') + N'"}';
DECLARE @Sql nvarchar(max) =
    CASE WHEN EXISTS (
        SELECT 1 FROM sys.database_scoped_credentials WHERE [name] = @CredentialUrl
    ) THEN N'ALTER' ELSE N'CREATE' END +
    N' DATABASE SCOPED CREDENTIAL ' + QUOTENAME(@CredentialUrl) +
    N' WITH IDENTITY = ''HTTPEndpointHeaders'', SECRET = N''' +
    REPLACE(@Secret, N'''', N'''''') + N''';';
EXEC sys.sp_executesql @Sql;

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE ai.ModelEndpoint
    SET IsActive = 0
    WHERE IsActive = 1 AND EndpointName <> @EndpointName;

    IF EXISTS (SELECT 1 FROM ai.ModelEndpoint WHERE EndpointName = @EndpointName)
        UPDATE ai.ModelEndpoint
        SET BaseUrl = @CredentialUrl,
            ModelId = @ModelId,
            CredentialName = @CredentialUrl,
            TimeoutSeconds = 180,
            IsActive = 1
        WHERE EndpointName = @EndpointName;
    ELSE
        INSERT ai.ModelEndpoint
            (EndpointName, BaseUrl, ModelId, CredentialName, TimeoutSeconds, IsActive)
        VALUES
            (@EndpointName, @CredentialUrl, @ModelId, @CredentialUrl, 180, 1);

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
'@ -Parameters @{
            '@ApiKey'        = $apiKey
            '@CredentialUrl' = $credentialUrl
            '@ModelId'       = $modelId
            '@EndpointName'  = $endpointName
        }

        Write-Host "Configured Azure Local Gateway model '$modelId'." -ForegroundColor Green
    }
    finally {
        if ($connection) {
            $connection.Dispose()
        }
        $apiKey = $null
        $encodedApiKey = $null
        $escapedApiKey = $null
        $curlConfig = $null
        $masterKeyPassword = $null
        $masterKeyBytes = $null
    }
}

if ($ConfigureModelOnly) {
    Set-AzureLocalGatewayEndpoint
    Write-Host 'Model endpoint configuration passed. Schema, seed data, and skill procedures were not redeployed.' -ForegroundColor Green
    return
}

if ($InitializeDatabase) {
    & $sqlcmd.Source -S $ServerInstance -d master -E -C -b -Q "IF DB_ID(N'$databaseName') IS NOT NULL THROW 50000, '$databaseName already exists. Initialization refused.', 1;"
    if ($LASTEXITCODE -ne 0) {
        throw "Initialization requires an absent $databaseName database. Existing data was not changed."
    }

    '00-create-database.sql',
    '01-schema.sql',
    '02-seed.sql' | ForEach-Object { Invoke-CaldovaSqlScript -Name $_ }
}
else {
    & $sqlcmd.Source -S $ServerInstance -d master -E -C -b -Q "IF DB_ID(N'$databaseName') IS NULL THROW 50000, '$databaseName does not exist. Use -InitializeDatabase.', 1;"
    if ($LASTEXITCODE -ne 0) {
        throw "$databaseName is missing. Run this script with -InitializeDatabase."
    }
}

'01b-ledger.sql',
'03-programmability.sql',
'test-packet.sql' | ForEach-Object { Invoke-CaldovaSqlScript -Name $_ }

Set-AzureLocalGatewayEndpoint

Invoke-CaldovaSqlScript -Name '07-rag.sql'

if ($TestFoundryAi) {
    Invoke-CaldovaSqlScript -Name 'test-foundry-ai.sql'
    Write-Host 'Database setup and live Foundry Local test passed.' -ForegroundColor Green
}
else {
    Write-Host 'Database setup passed. Use -TestFoundryAi to run test-foundry-ai.sql.' -ForegroundColor Green
}