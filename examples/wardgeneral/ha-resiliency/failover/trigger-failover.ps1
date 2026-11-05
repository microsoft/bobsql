<#
.SYNOPSIS
    Preview or trigger one manual Azure SQL database failover.

.DESCRIPTION
    Resolves the exact existing database with Azure CLI and prints the REST
    request. The default is preview-only. Pass -Execute only after the retry
    probe is visibly succeeding in another terminal and the intrusive action
    has been approved. Azure allows one failover call per database every 15
    minutes.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $ResourceGroup = ($env:RG ?? 'rg-collierhealth'),
    [string] $Server,
    [string] $Database,
    [switch] $Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$loadEnv = Join-Path $PSScriptRoot '..' '..' 'first-app' 'load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }

if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') {
    throw 'No server. Fill in WardGeneral__Server in first-app/wardgeneral.env, set the environment variable, or pass -Server explicitly.'
}

$logicalServer = $Server -replace '\.database\.windows\.net$', ''
$account = az account show --output json | ConvertFrom-Json
$databaseResource = az sql db show `
    --resource-group $ResourceGroup `
    --server $logicalServer `
    --name $Database `
    --output json | ConvertFrom-Json

if ($databaseResource.edition -ne 'Hyperscale') {
    throw "Database '$Database' is '$($databaseResource.edition)', not Hyperscale."
}

# replicaType is optional and defaults to the primary. Omitting it also avoids
# cmd.exe treating the query-string ampersand as a command separator when the
# Azure CLI entry point is az.cmd on Windows.
$requestUrl = "https://management.azure.com$($databaseResource.id)/failover?api-version=2025-01-01"

Write-Host '--- Manual failover plan ---'
Write-Host "Subscription : $($account.name) ($($account.id))"
Write-Host "Database     : $Database @ $logicalServer"
Write-Host "Resource ID  : $($databaseResource.id)"
Write-Host "Edition      : $($databaseResource.edition)"
Write-Host "Zone redundant: $($databaseResource.zoneRedundant)"
Write-Host 'Throttle     : one failover call per database every 15 minutes'
Write-Host "Request      : POST $requestUrl"

if (-not $Execute) {
    Write-Host ''
    Write-Host 'PREVIEW ONLY. After approval, start the retry probe in another terminal; rerun with -Execute after several OK rows.' -ForegroundColor Yellow
    return
}

Write-Host ''
Write-Host "FailoverRequestedUtc=$([DateTimeOffset]::UtcNow.ToString('O'))"
az rest --method post --url $requestUrl --output none
Write-Host "FailoverAcceptedUtc=$([DateTimeOffset]::UtcNow.ToString('O'))"
Write-Host 'The API accepted the request. Keep the probe running until successful requests resume.'
