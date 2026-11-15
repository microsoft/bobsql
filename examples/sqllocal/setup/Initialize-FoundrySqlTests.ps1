[CmdletBinding()]
param(
    [switch]$ApplicationVectorSearch,
    [string]$ServerInstance = 'localhost',
    [string]$KubeconfigPath = 'C:\setup\caldova-admin.kubeconfig'
)

$ErrorActionPreference = 'Stop'
$kubectl = Get-Command kubectl -ErrorAction Stop
if (-not (Test-Path -LiteralPath $KubeconfigPath -PathType Leaf)) {
    throw "Protected kubeconfig was not found at '$KubeconfigPath'."
}

$builder = [Data.SqlClient.SqlConnectionStringBuilder]::new()
$builder['Data Source'] = $ServerInstance
$builder['Initial Catalog'] = 'master'
$builder['Integrated Security'] = $true
$builder['Encrypt'] = $true
$builder['TrustServerCertificate'] = $true
$builder['Application Name'] = 'Caldova isolated Foundry SQL tests'
$connection = [Data.SqlClient.SqlConnection]::new($builder.ConnectionString)

try {
    $connection.Open()
    $command = $connection.CreateCommand()
    try {
        $command.CommandText = @'
IF NOT EXISTS (
    SELECT 1 FROM sys.configurations
    WHERE name = N'external rest endpoint enabled' AND CONVERT(int, value_in_use) = 1
)
    THROW 50000, 'Enable external rest endpoint enabled before initializing these tests.', 1;

IF @ApplicationVectorSearch = 1 AND DB_ID(N'CaldovaRegionalCare') IS NULL
    THROW 50000, 'CaldovaRegionalCare must already exist for application vector search.', 1;

IF @ApplicationVectorSearch = 0 AND DB_ID(N'CaldovaFoundryModelTests') IS NULL
    CREATE DATABASE CaldovaFoundryModelTests;
'@
        [void]$command.Parameters.Add('@ApplicationVectorSearch', [Data.SqlDbType]::Bit)
        $command.Parameters['@ApplicationVectorSearch'].Value = [bool]$ApplicationVectorSearch
        [void]$command.ExecuteNonQuery()
    }
    finally {
        $command.Dispose()
    }

    $targetDatabase = if ($ApplicationVectorSearch) { 'CaldovaRegionalCare' } else { 'CaldovaFoundryModelTests' }
    $connection.ChangeDatabase($targetDatabase)
    $command = $connection.CreateCommand()
    try {
        $command.CommandText = 'ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;'
        [void]$command.ExecuteNonQuery()
        Write-Host "Enabled PREVIEW_FEATURES in $targetDatabase for float16 vectors."
    }
    finally {
        $command.Dispose()
    }

    $bytes = [byte[]]::new(48)
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($bytes)
    }
    finally {
        $random.Dispose()
    }
    $masterKeyPassword = [Convert]::ToBase64String($bytes) + '!aA1'
    $command = $connection.CreateCommand()
    try {
        $command.CommandText = @'
IF NOT EXISTS (
    SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##'
)
BEGIN
    DECLARE @Sql nvarchar(max) =
        N'CREATE MASTER KEY ENCRYPTION BY PASSWORD = N''' +
        REPLACE(@MasterKeyPassword, N'''', N'''''') + N''';';
    EXEC sys.sp_executesql @Sql;
END;
'@
        [void]$command.Parameters.Add('@MasterKeyPassword', [Data.SqlDbType]::NVarChar, 128)
        $command.Parameters['@MasterKeyPassword'].Value = $masterKeyPassword
        [void]$command.ExecuteNonQuery()
    }
    finally {
        $command.Dispose()
        $masterKeyPassword = $null
    }

    $deployments = if ($ApplicationVectorSearch) { @('nemotron-3-embed-1b-bf16') } else { @('gpt-oss-20b', 'nemotron-3-embed-1b-bf16') }
    foreach ($deploymentName in $deployments) {
        $encodedApiKey = & $kubectl.Source `
            --kubeconfig $KubeconfigPath `
            get secret "$deploymentName-api-keys" `
            --namespace foundry-local-operator `
            --request-timeout=15s `
            --output 'jsonpath={.data.primary-key}'
        if ($LASTEXITCODE -ne 0 -or -not $encodedApiKey) {
            throw "Unable to retrieve the API key for '$deploymentName'."
        }
        $apiKey = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedApiKey))
        if ([string]::IsNullOrWhiteSpace($apiKey) -or $apiKey.Length -gt 4000) {
            throw "The API key for '$deploymentName' is empty or too long."
        }
        $credentialName = "https://192.0.2.10/$deploymentName"
        $command = $connection.CreateCommand()
        try {
            $command.CommandText = @'
IF EXISTS (
    SELECT 1 FROM sys.database_scoped_credentials
    WHERE name = @CredentialName AND credential_identity <> N'HTTPEndpointHeaders'
)
    THROW 50000, 'Existing credential has an unexpected identity; no replacement was made.', 1;

DECLARE @Secret nvarchar(max) = N'{"api-key":"' + STRING_ESCAPE(@ApiKey, 'json') + N'"}';
DECLARE @Sql nvarchar(max) =
    CASE WHEN EXISTS (
        SELECT 1 FROM sys.database_scoped_credentials WHERE name = @CredentialName
    ) THEN N'ALTER' ELSE N'CREATE' END +
    N' DATABASE SCOPED CREDENTIAL ' + QUOTENAME(@CredentialName) +
    N' WITH IDENTITY = ''HTTPEndpointHeaders'', SECRET = N''' +
    REPLACE(@Secret, N'''', N'''''') + N''';';
EXEC sys.sp_executesql @Sql;
'@
            [void]$command.Parameters.Add('@CredentialName', [Data.SqlDbType]::NVarChar, 128)
            $command.Parameters['@CredentialName'].Value = $credentialName
            [void]$command.Parameters.Add('@ApiKey', [Data.SqlDbType]::NVarChar, 4000)
            $command.Parameters['@ApiKey'].Value = $apiKey
            [void]$command.ExecuteNonQuery()
            Write-Host "Configured encrypted $targetDatabase credential: $credentialName"
        }
        finally {
            $command.Dispose()
            $apiKey = $null
            $encodedApiKey = $null
        }
    }
    Write-Host "Embedding credentials are ready in $targetDatabase and persist across SQL restarts." -ForegroundColor Green
    Write-Host 'No server setting or briefing model configuration was changed.'
}
finally {
    $connection.Dispose()
    $apiKey = $null
    $encodedApiKey = $null
    $masterKeyPassword = $null
}
