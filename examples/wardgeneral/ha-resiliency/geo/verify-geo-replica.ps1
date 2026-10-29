<#
.SYNOPSIS
    Verify the Ward General Hyperscale geo-replica and replication link.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $ResourceGroup = ($env:RG ?? 'rg-collierhealth'),
    [string] $SourceServer,
    [string] $Database,
    [string] $TargetServer
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
    throw "Target server '$TargetServer' is not a valid Azure SQL logical server name."
}

$source = az sql db show `
    --resource-group $ResourceGroup `
    --server $SourceServer `
    --name $Database `
    --query '{id:id,status:status,edition:edition,sku:currentServiceObjectiveName,location:location}' `
    --output json | ConvertFrom-Json
$targetServerResource = az sql server show `
    --resource-group $ResourceGroup `
    --name $TargetServer `
    --query '{name:name,location:location,identityType:identity.type,principalId:identity.principalId,tags:tags}' `
    --output json | ConvertFrom-Json
$secondary = az sql db show `
    --resource-group $ResourceGroup `
    --server $TargetServer `
    --name $Database `
    --query '{id:id,status:status,edition:edition,sku:currentServiceObjectiveName,location:location,sourceDatabaseId:sourceDatabaseId,secondaryType:secondaryType,zoneRedundant:zoneRedundant,haReplicas:highAvailabilityReplicaCount,backupRedundancy:currentBackupStorageRedundancy}' `
    --output json | ConvertFrom-Json

if ($source.status -ne 'Online' -or $source.edition -ne 'Hyperscale') {
    throw "Source is not an online Hyperscale database: status='$($source.status)', edition='$($source.edition)'."
}
if ($targetServerResource.location -ne 'eastus2') {
    throw "Target server is in '$($targetServerResource.location)', not 'eastus2'."
}
$targetTags = @{}
if ($targetServerResource.tags) {
    $targetServerResource.tags.PSObject.Properties | ForEach-Object { $targetTags[$_.Name] = $_.Value }
}
if ($targetTags['application'] -ne 'ward-general-ehr' -or $targetTags['environment'] -ne 'sandbox') {
    throw 'Target server is not tagged as a Ward General sandbox.'
}
if ($targetServerResource.identityType -notmatch 'SystemAssigned' -or -not $targetServerResource.principalId) {
    throw 'Target server does not have the required system-assigned identity.'
}
if ($secondary.status -ne 'Online' -or $secondary.edition -ne 'Hyperscale') {
    throw "Secondary is not an online Hyperscale database: status='$($secondary.status)', edition='$($secondary.edition)'."
}
if ($secondary.haReplicas -ne 0 -or $secondary.zoneRedundant) {
    throw "Secondary does not have the expected lower-cost topology: haReplicas='$($secondary.haReplicas)', zoneRedundant='$($secondary.zoneRedundant)'."
}
if ($secondary.sourceDatabaseId -and $secondary.sourceDatabaseId -ne $source.id) {
    throw "Secondary sourceDatabaseId does not match '$($source.id)'."
}

$sourceLinks = @(az sql db replica list-links `
    --resource-group $ResourceGroup `
    --server $SourceServer `
    --name $Database `
    --output json | ConvertFrom-Json)
$targetLinks = @(az sql db replica list-links `
    --resource-group $ResourceGroup `
    --server $TargetServer `
    --name $Database `
    --output json | ConvertFrom-Json)

$sourceLink = @($sourceLinks | Where-Object { $_.partnerServer -eq $TargetServer })
$targetLink = @($targetLinks | Where-Object { $_.partnerServer -eq $SourceServer })
if ($sourceLink.Count -ne 1 -or $targetLink.Count -ne 1) {
    throw "Expected one replication link on each side; found source=$($sourceLink.Count), target=$($targetLink.Count)."
}

Write-Host '--- Source database ---'
$source | Format-List
Write-Host '--- Target logical server ---'
$targetServerResource | Format-List
Write-Host '--- Geo-secondary database ---'
$secondary | Format-List
Write-Host '--- Replication link from source ---'
$sourceLink[0] | Format-List
Write-Host '--- Replication link from target ---'
$targetLink[0] | Format-List
Write-Host 'GeoReplicaVerification=PASS'