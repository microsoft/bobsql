[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Schema', 'Network', 'Verify', 'Storage')]
    [string]$Phase,
    [switch]$IncludeStorageFill
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"
if ($Phase -eq 'Storage') {
    & "$PSScriptRoot\11-fill-demo-storage.ps1"
    return
}
Import-Module SqlServer -ErrorAction Stop

if ($AppName -notmatch '^app-caldova-network-[a-z0-9-]+$' -or $AppName.Length -gt 60 -or $CaldovaDatabase -ne 'caldova-scheduling') {
    throw 'The SQL files name the Caldova databases explicitly and receive the app identity as SQLCMD variable AppName. Review them before deploying to a different environment.'
}

$databaseNames = @($CaldovaDatabase) + @($AcquiredDatabases | ForEach-Object { $_.Name })
$sqlRoot = Join-Path $PSScriptRoot '..\sql'

function Invoke-SchedulingFile {
    param([string]$Database, [string]$File, [string[]]$Variables = @())
    Write-Step "$Database : $File"
    $token = Invoke-Az @('account', 'get-access-token', '--subscription', $SubscriptionId,
        '--resource', 'https://database.windows.net/', '--output', 'json')
    $options = @{
        ServerInstance = $SqlServerFqdn; Database = $Database; AccessToken = $token.accessToken
        InputFile = (Join-Path $sqlRoot $File); ConnectionTimeout = 90; QueryTimeout = 120
        Encrypt = 'Mandatory'; AbortOnError = $true; OutputSqlErrors = $true; ErrorAction = 'Stop'
    }
    if ($Variables.Count -gt 0) { $options.Variable = $Variables }
    Invoke-Sqlcmd @options
    Write-Ok "$File completed"
}

if ($Phase -ne 'Schema') {
    $pool = Invoke-Az @('sql', 'elastic-pool', 'show', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroup, '--server', $SqlServerName, '--name', $ElasticPoolName, '--output', 'json')
    foreach ($name in $databaseNames) {
        $database = Invoke-Az @('sql', 'db', 'show', '--subscription', $SubscriptionId,
            '--resource-group', $ResourceGroup, '--server', $SqlServerName, '--name', $name, '--output', 'json')
        if ($database.elasticPoolId -ne $pool.id -or $database.status -ne 'Online') {
            throw "$name must be online in $ElasticPoolName before deploying or verifying native cross-database SQL."
        }
    }
}

switch ($Phase) {
    'Schema' {
        Invoke-SchedulingFile 'master' '00-app-login.sql' -Variables @("AppName=$AppName")
        foreach ($name in $databaseNames) {
            Invoke-SchedulingFile $name '01-scheduling-schema.sql'
        }
        if ($IncludeStorageFill) { & "$PSScriptRoot\11-fill-demo-storage.ps1" }
    }
    'Network' {
        $token = Invoke-Az @('account', 'get-access-token', '--subscription', $SubscriptionId,
            '--resource', 'https://database.windows.net/', '--output', 'json')
        $login = Invoke-Sqlcmd -ServerInstance $SqlServerFqdn -Database 'master' -AccessToken $token.accessToken `
            -Query "SELECT CONVERT(varchar(172), sid, 1) AS AppLoginSid FROM sys.server_principals WHERE name = N'$AppName';" `
            -ConnectionTimeout 90 -QueryTimeout 120 -Encrypt Mandatory -AbortOnError -ErrorAction Stop
        if ($null -eq $login -or $login.AppLoginSid -notmatch '^0x[0-9a-fA-F]{32}$') {
            throw 'The expected app login must exist in master with a valid SID before deploying the network view.'
        }
        Invoke-SchedulingFile $CaldovaDatabase '02-network-view.sql'
        foreach ($name in $databaseNames) {
            Invoke-SchedulingFile $name '03-app-permissions.sql' -Variables @("AppLoginSid=$($login.AppLoginSid)", "AppName=$AppName")
        }
    }
    'Verify' {
        Invoke-SchedulingFile $CaldovaDatabase '04-verify-read.sql'
        Write-Host 'This verified the deployment identity only. Verify app-managed-identity reads and booking in the deployed app.'
    }
}
