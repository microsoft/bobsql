<#
.SYNOPSIS
    Preview or remove the Ward General geo-replica and target logical server.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $ResourceGroup = ($env:RG ?? 'rg-collierhealth'),
    [string] $SourceServer,
    [string] $Database,
    [string] $TargetServer,
    [switch] $Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$loadEnv = Join-Path $PSScriptRoot '..' '..' 'first-app' 'load-env.ps1'
& $loadEnv -Require @('WardGeneral__Server', 'WardGeneral__Database') -Quiet
if (-not $SourceServer) { $SourceServer = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database }
$SourceServer = $SourceServer -replace '\.database\.windows\.net$', ''

if ([string]::IsNullOrWhiteSpace($TargetServer) -or $TargetServer -match '<[^>]*>') {
    throw 'Pass -TargetServer with the logical server name used by deploy-geo-replica.ps1.'
}
if ($TargetServer -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$') {
    throw "Refusing cleanup: '$TargetServer' is not a valid Azure SQL logical server name."
}
if ($SourceServer -eq $TargetServer) {
    throw 'Refusing cleanup because source and target server names are identical.'
}

$target = az sql server show `
    --resource-group $ResourceGroup `
    --name $TargetServer `
    --query '{id:id,name:name,location:location,identityType:identity.type,principalId:identity.principalId,tags:tags}' `
    --output json | ConvertFrom-Json
$secondary = az sql db show `
    --resource-group $ResourceGroup `
    --server $TargetServer `
    --name $Database `
    --query '{id:id,name:name,status:status,edition:edition,sourceDatabaseId:sourceDatabaseId,secondaryType:secondaryType}' `
    --output json | ConvertFrom-Json
$source = az sql db show `
    --resource-group $ResourceGroup `
    --server $SourceServer `
    --name $Database `
    --query '{id:id,name:name,status:status,edition:edition}' `
    --output json | ConvertFrom-Json
$links = @(az sql db replica list-links `
    --resource-group $ResourceGroup `
    --server $SourceServer `
    --name $Database `
    --output json | ConvertFrom-Json)
$targetLink = @($links | Where-Object { $_.partnerServer -eq $TargetServer })
$targetDatabases = @(az sql db list `
    --resource-group $ResourceGroup `
    --server $TargetServer `
    --query '[].name' `
    --output tsv)

if ($target.location -ne 'eastus2') {
    throw "Refusing cleanup: target server is in '$($target.location)', not 'eastus2'."
}
$targetTags = @{}
if ($target.tags) {
    $target.tags.PSObject.Properties | ForEach-Object { $targetTags[$_.Name] = $_.Value }
}
if ($targetTags['application'] -ne 'ward-general-ehr' -or $targetTags['environment'] -ne 'sandbox') {
    throw 'Refusing cleanup: target server is not tagged as a Ward General sandbox.'
}
$unexpectedDatabases = @($targetDatabases | Where-Object { $_ -notin @('master', $Database) })
if ($unexpectedDatabases.Count -gt 0) {
    throw "Refusing cleanup: target server contains unexpected database(s): $($unexpectedDatabases -join ', ')."
}
if ($secondary.sourceDatabaseId -and $secondary.sourceDatabaseId -ne $source.id) {
    throw "Refusing cleanup: target database does not identify '$($source.id)' as its source."
}
if ($targetLink.Count -ne 1) {
    throw "Refusing cleanup: expected one replication link to '$TargetServer'; found $($targetLink.Count)."
}

Write-Host '--- Geo-replica cleanup plan ---'
Write-Host "Source retained      : $($source.id)"
Write-Host "Replication link     : $($targetLink[0].id)"
Write-Host "Secondary removed    : $($secondary.id)"
Write-Host "Target server deleted: $($target.id)"
if (-not $Execute) {
    Write-Host 'PREVIEW ONLY. Rerun with -Execute only after geo-replica testing is complete.' -ForegroundColor Yellow
    return
}

az sql db replica delete-link `
    --resource-group $ResourceGroup `
    --server $SourceServer `
    --name $Database `
    --partner-server $TargetServer `
    --yes `
    --output none
Write-Host "GeoReplicationLinkRemoved=$Database@$TargetServer"

az sql server delete `
    --resource-group $ResourceGroup `
    --name $TargetServer `
    --yes `
    --output none
Write-Host "TargetServerDeleted=$TargetServer"