<#
.SYNOPSIS
    Capture Azure Resource Health before or after failover.

.DESCRIPTION
    Resolves the exact Ward General database and queries its current Resource
    Health status directly. Evidence is saved as JSON.

    In the Before phase, the script refuses to approve a failover when Resource
    Health isn't Available. The After phase records the same evidence without
    applying the preflight gate.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Before', 'After')]
    [string] $Phase = 'Before',
    [string] $ResourceGroup = ($env:RG ?? 'rg-collierhealth'),
    [string] $Server,
    [string] $Database,
    [string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$loadEnv = Join-Path $PSScriptRoot '..' '..' 'first-app' 'load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }
if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') {
    throw 'No Ward General server is configured.'
}

$logicalServer = $Server -replace '\.database\.windows\.net$', ''
$account = az account show --query '{name:name, id:id}' --output json | ConvertFrom-Json
$databaseResource = az sql db show `
    --resource-group $ResourceGroup `
    --server $logicalServer `
    --name $Database `
    --query '{id:id, edition:edition, location:location}' `
    --output json | ConvertFrom-Json
if ($databaseResource.edition -ne 'Hyperscale') {
    throw "Database '$Database' is '$($databaseResource.edition)', not Hyperscale."
}

if (-not $OutputDirectory) {
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) "wardgeneral-ha-resiliency-health-$($Phase.ToLowerInvariant())-$stamp"
}
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$OutputDirectory = (Resolve-Path $OutputDirectory).Path

$resourceHealthUrl = "https://management.azure.com$($databaseResource.id)/providers/Microsoft.ResourceHealth/availabilityStatuses/current?api-version=2024-02-01"
$resourceHealth = az rest --method get --url $resourceHealthUrl --output json | ConvertFrom-Json
$resourceHealthPath = Join-Path $OutputDirectory 'resource-health.json'
$resourceHealth | ConvertTo-Json -Depth 20 |
    Set-Content -LiteralPath $resourceHealthPath -Encoding utf8NoBOM

$sampledAtUtc = [DateTimeOffset]::UtcNow
Write-Host "--- High Availability and Resiliency health check: $Phase ---"
Write-Host "SampledAtUtc   : $($sampledAtUtc.ToString('O'))"
Write-Host "Subscription   : $($account.name) ($($account.id))"
Write-Host "Database       : $Database @ $logicalServer"
Write-Host "Resource ID    : $($databaseResource.id)"
Write-Host "Region         : $($databaseResource.location)"
Write-Host "Resource Health: $($resourceHealth.properties.availabilityState)"
Write-Host "ReportedAtUtc  : $($resourceHealth.properties.reportedTime)"
Write-Host "Summary        : $($resourceHealth.properties.summary)"
Write-Host "ResourceHealthEvidence=$resourceHealthPath"

if ($Phase -eq 'Before') {
    if ($resourceHealth.properties.availabilityState -ne 'Available') {
        throw "Failover preflight blocked: Resource Health is '$($resourceHealth.properties.availabilityState)', not 'Available'."
    }
    Write-Host 'FailoverHealthPrecheck=PASS'
}
else {
    Write-Host 'FailoverHealthPostcheck=RECORDED'
}
