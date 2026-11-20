#requires -Version 7.0
#requires -Modules SqlServer
<#
.SYNOPSIS
Deploys web procedures and configures a restricted local application identity.
.DESCRIPTION
Run after build-database.ps1, with the web app stopped. Rotates the contained
CustomerServiceDeskWeb user's password and stores its connection in .NET user
secrets outside the repository. Never uses the registry credential file.
#>
[CmdletBinding()]
param(
    [PSCredential]$SqlCredential,
    [switch]$UseContainerCredentials
)
$ErrorActionPreference = 'Stop'
Import-Module SqlServer -ErrorAction Stop
if ($UseContainerCredentials) {
    if ($SqlCredential) { throw 'Choose either -SqlCredential or -UseContainerCredentials.' }
    $settings = docker inspect --format '{{json .Config.Env}}' sqldbcontainer
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read local container settings.' }
    $password = @($settings | ConvertFrom-Json | Where-Object { $_.StartsWith('MSSQL_SA_PASSWORD=') })
    if ($password.Count -ne 1) { throw 'The local container has no unique initial SQL password setting.' }
    $SqlCredential = [PSCredential]::new('sa',
        [Net.NetworkCredential]::new('', $password[0].Substring('MSSQL_SA_PASSWORD='.Length)).SecurePassword)
    $settings = $null
    $password = $null
}
if (-not $SqlCredential) {
    $SqlCredential = Get-Credential -UserName sa -Message 'Local SQL setup administrator'
    if (-not $SqlCredential) { throw 'A SQL setup credential is required.' }
}
$builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new()
$builder['Data Source'] = 'localhost,14332'
$builder['Initial Catalog'] = 'CustomerServiceDesk'
$builder['Encrypt'] = $true
$builder['TrustServerCertificate'] = $true
$builder['Application Name'] = 'CustomerServiceDesk.AppSetup'
$connection = [Microsoft.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
$securePassword = $SqlCredential.Password.Copy()
$securePassword.MakeReadOnly()
$connection.Credential = [Microsoft.Data.SqlClient.SqlCredential]::new($SqlCredential.UserName, $securePassword)
try {
    $connection.Open()
    foreach ($name in @('08-app-procedures.sql', '09-verify-app.sql')) {
        $sql = Get-Content -LiteralPath (Join-Path $PSScriptRoot $name) -Raw
        $sql = [regex]::Replace($sql, '(?i)^\s*USE\s+CustomerServiceDesk\s*;', '')
        foreach ($batch in [regex]::Split($sql, '(?im)^\s*GO\s*\r?$')) {
            if ([string]::IsNullOrWhiteSpace($batch)) { continue }
            $command = $connection.CreateCommand()
            try {
                $command.CommandText = $batch
                $command.CommandTimeout = 60
                [void]$command.ExecuteNonQuery()
            } finally { $command.Dispose() }
        }
        Write-Host "Completed $name"
    }
    $appPassword = 'Aa1!' + [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
    $command = $connection.CreateCommand()
    try {
        # Password DDL requires a literal; QUOTENAME escapes the bound value on the server.
        $command.CommandText = @'
DECLARE @Statement nvarchar(max) =
    CASE WHEN DATABASE_PRINCIPAL_ID(N'CustomerServiceDeskWeb') IS NULL
        THEN N'CREATE USER CustomerServiceDeskWeb WITH PASSWORD = '
        ELSE N'ALTER USER CustomerServiceDeskWeb WITH PASSWORD = ' END
    + QUOTENAME(@Password, '''') + N';';
EXEC sys.sp_executesql @Statement;
IF IS_ROLEMEMBER(N'CustomerServiceDeskApp', N'CustomerServiceDeskWeb') <> 1
    ALTER ROLE CustomerServiceDeskApp ADD MEMBER CustomerServiceDeskWeb;
'@
        [void]$command.Parameters.Add('@Password', [Data.SqlDbType]::NVarChar, 100)
        $command.Parameters['@Password'].Value = $appPassword
        [void]$command.ExecuteNonQuery()
    } finally { $command.Dispose() }
    $builder['User ID'] = 'CustomerServiceDeskWeb'
    $builder['Password'] = $appPassword
    $builder['Application Name'] = 'CustomerServiceDesk.Web'
    $builder['Connect Timeout'] = 5
    @{ 'ConnectionStrings:CustomerServiceDesk' = $builder.ConnectionString } |
        ConvertTo-Json -Compress |
        dotnet user-secrets set --project (Join-Path $PSScriptRoot 'app\CustomerServiceDesk.csproj')
    if ($LASTEXITCODE -ne 0) { throw 'Cannot save app user secrets. Correct the failure and rerun setup before starting the app.' }
    Write-Host 'Application procedures deployed; restricted local identity configured in .NET user secrets.'
} finally {
    $connection.Dispose()
    $appPassword = $null
    $builder.Clear()
}
