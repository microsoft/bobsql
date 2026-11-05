<#
.SYNOPSIS
    Preview or delete only the named High Availability and Resiliency restored database.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $RestoredDatabase,
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
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') { throw 'No Ward General server is configured.' }
if ($RestoredDatabase -notmatch '^wardgeneral-pitr-') {
    throw "Refusing to delete '$RestoredDatabase': High Availability and Resiliency restored database names must start with 'wardgeneral-pitr-'."
}

$logicalServer = $Server -replace '\.database\.windows\.net$', ''
$resource = az sql db show `
    --resource-group $ResourceGroup `
    --server $logicalServer `
    --name $RestoredDatabase `
    --query '{id:id, name:name, edition:edition, sourceDatabaseId:sourceDatabaseId}' `
    --output json | ConvertFrom-Json
if ($resource.sourceDatabaseId -and
    $resource.sourceDatabaseId -notmatch "/databases/$([Regex]::Escape($Database))$") {
    throw "Refusing to delete '$RestoredDatabase': its sourceDatabaseId does not identify '$Database'."
}
if (-not $resource.sourceDatabaseId) {
    Write-Warning 'Azure did not retain sourceDatabaseId on the completed restored resource; verify the exact resource shown below before approving deletion.'
}

Write-Host '--- PITR cleanup plan ---'
$resource | Format-List
if (-not $Execute) {
    Write-Host 'PREVIEW ONLY. Rerun with -Execute after the restored data has been verified.' -ForegroundColor Yellow
    return
}

az sql db delete `
    --resource-group $ResourceGroup `
    --server $logicalServer `
    --name $RestoredDatabase `
    --yes
Write-Host "Deleted=$RestoredDatabase"
