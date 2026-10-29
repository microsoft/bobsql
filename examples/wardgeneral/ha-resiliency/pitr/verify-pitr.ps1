<#
.SYNOPSIS
    Verify the restored resource and Ward General data for testing.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $RestoredDatabase,
    [string] $ResourceGroup = ($env:RG ?? 'rg-collierhealth'),
    [string] $Server,
    [string] $Database,
    [string] $SqlCmd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$loadEnv = Join-Path $PSScriptRoot '..' '..' 'first-app' 'load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }
if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') { throw 'No Ward General server is configured.' }
if ($RestoredDatabase -notmatch '^wardgeneral-pitr-') {
    throw "Verification target '$RestoredDatabase' is outside this demo. High Availability and Resiliency restored database names must start with 'wardgeneral-pitr-'."
}

$logicalServer = $Server -replace '\.database\.windows\.net$', ''
$resource = az sql db show `
    --resource-group $ResourceGroup `
    --server $logicalServer `
    --name $RestoredDatabase `
    --query '{name:name, status:status, edition:edition, sku:currentServiceObjectiveName, computeModel:computeModel, minCapacity:minCapacity, sourceDatabaseId:sourceDatabaseId, restorePointInTime:restorePointInTime}' `
    --output json | ConvertFrom-Json
if ($resource.status -ne 'Online') { throw "Restored database status is '$($resource.status)', not 'Online'." }
if ($resource.edition -ne 'Hyperscale' -or $resource.sku -notmatch '^HS_S_') {
    throw "Restored database is not Hyperscale serverless: edition='$($resource.edition)', sku='$($resource.sku)'."
}
if ($resource.sourceDatabaseId -and
    $resource.sourceDatabaseId -notmatch "/databases/$([Regex]::Escape($Database))$") {
    throw "Restored database sourceDatabaseId does not identify '$Database'."
}
if (-not $resource.sourceDatabaseId) {
    Write-Warning 'Azure did not retain sourceDatabaseId on the completed restored resource; use the restore operation record and data checks as recovery evidence.'
}

Write-Host '--- Restored test database ---'
$resource | Format-List

$sqlcmdPath = @(
    $SqlCmd,
    $env:SQLCMD,
    (Join-Path $env:LOCALAPPDATA 'Programs\sqlcmd\sqlcmd.exe'),
    'C:\Program Files\SqlCmd\sqlcmd.exe',
    (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $sqlcmdPath) { throw 'The new sqlcmd was not found. Install it with: winget install --id Microsoft.Sqlcmd' }

$script = Join-Path $PSScriptRoot '..' '..' 'getting-started' 'verify-data.sql'
Write-Host ''
Write-Host '--- Ward General schema and data checks ---'
& $sqlcmdPath -S $Server -d $RestoredDatabase -G -b -i $script
if ($LASTEXITCODE -ne 0) { throw 'Restored test-database verification failed.' }

Write-Host ''
Write-Host 'PitrVerification=PASS'
