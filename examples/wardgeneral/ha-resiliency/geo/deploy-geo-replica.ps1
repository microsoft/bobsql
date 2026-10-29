<#
.SYNOPSIS
    Preview or deploy the Ward General Hyperscale geo-replica.

.DESCRIPTION
    Creates a reader-named Entra-only logical server in East US 2 with a
    system-assigned identity and the signed-in user's Entra identity as
    administrator, then creates wardgeneral as a geo-secondary. The source
    database remains online and writable. Preview-only unless -Execute is
    supplied.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $ResourceGroup = ($env:RG ?? 'rg-collierhealth'),
    [string] $SourceServer,
    [string] $Database,
    [string] $TargetServer,
    [string] $TargetLocation = 'eastus2',
    [switch] $Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$loadEnv = Join-Path $PSScriptRoot '..' '..' 'first-app' 'load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }

if (-not $SourceServer) { $SourceServer = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
if ([string]::IsNullOrWhiteSpace($SourceServer) -or $SourceServer -match '<[^>]*>') {
    throw 'No source server. Fill in WardGeneral__Server in first-app/wardgeneral.env, set the environment variable, or pass -SourceServer explicitly.'
}

$SourceServer = $SourceServer -replace '\.database\.windows\.net$', ''
if ([string]::IsNullOrWhiteSpace($TargetServer) -or $TargetServer -match '<[^>]*>') {
    throw 'Pass -TargetServer with a globally unique Azure SQL logical server name.'
}
if ($TargetServer -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$') {
    throw "Target server '$TargetServer' must contain 1-63 lowercase letters, numbers, or hyphens; it cannot begin or end with a hyphen."
}
if ($TargetLocation -ne 'eastus2') {
    throw "Target location '$TargetLocation' is outside this example. Use eastus2."
}
if ($SourceServer -eq $TargetServer) {
    throw 'The source and target logical servers must be different.'
}

$account = az account show --output json | ConvertFrom-Json
$signedInUser = az ad signed-in-user show `
    --query '{id:id,userPrincipalName:userPrincipalName,displayName:displayName}' `
    --output json | ConvertFrom-Json
if (-not $signedInUser.id -or -not $signedInUser.userPrincipalName) {
    throw 'Azure CLI did not return the signed-in user object ID and user principal name.'
}

$source = az sql db show `
    --resource-group $ResourceGroup `
    --server $SourceServer `
    --name $Database `
    --output json | ConvertFrom-Json
if ($source.edition -ne 'Hyperscale') {
    throw "Source database '$Database' is '$($source.edition)', not Hyperscale."
}

$sourceProtector = az sql server tde-key show `
    --resource-group $ResourceGroup `
    --server $SourceServer `
    --output json | ConvertFrom-Json
$usesCustomerManagedKey = $sourceProtector.serverKeyType -eq 'AzureKeyVault'
$protectorKeyId = $null
$protectorVaultName = $null
$protectorKeyName = $null
$protectorVault = $null
if ($usesCustomerManagedKey) {
    if ($sourceProtector.uri -notmatch '^https://([^.]+)\.vault\.azure\.net/keys/([^/]+)(?:/[^/]+)?$') {
        throw "Source TDE protector URI '$($sourceProtector.uri)' is not a supported Azure Key Vault key URI."
    }
    $protectorVaultName = $Matches[1]
    $protectorKeyName = $Matches[2]
    $protectorKeyId = if ($sourceProtector.autoRotationEnabled) {
        "https://$protectorVaultName.vault.azure.net/keys/$protectorKeyName"
    } else {
        $sourceProtector.uri
    }
    $protectorVault = az keyvault show `
        --name $protectorVaultName `
        --output json | ConvertFrom-Json
}

$backupRedundancy = $source.requestedBackupStorageRedundancy
if (-not $backupRedundancy) { $backupRedundancy = $source.currentBackupStorageRedundancy }
if (-not $backupRedundancy) {
    throw "Azure did not return backup-storage redundancy for '$Database'."
}
$targetHaReplicas = 0
$targetZoneRedundant = $false

$target = $null
$priorNativePreference = $PSNativeCommandUseErrorActionPreference
$PSNativeCommandUseErrorActionPreference = $false
$targetJson = az sql server show `
    --resource-group $ResourceGroup `
    --name $TargetServer `
    --output json 2>$null
$targetLookupExit = $LASTEXITCODE
$PSNativeCommandUseErrorActionPreference = $priorNativePreference
if ($targetLookupExit -eq 0) {
    $target = $targetJson | ConvertFrom-Json
    $targetTags = @{}
    if ($target.tags) {
        $target.tags.PSObject.Properties | ForEach-Object { $targetTags[$_.Name] = $_.Value }
    }
    if ($targetTags['application'] -ne 'ward-general-ehr' -or $targetTags['environment'] -ne 'sandbox') {
        throw "Existing server '$TargetServer' is not tagged as a Ward General sandbox. Refusing to modify it."
    }
} elseif ($targetLookupExit -ne 3) {
    throw "Could not determine whether target server '$TargetServer' exists; Azure CLI exited with code $targetLookupExit."
}

$geo = $null
if ($target) {
    if ($target.location -ne $TargetLocation) {
        throw "Existing server '$TargetServer' is in '$($target.location)', not '$TargetLocation'."
    }
    if ($target.identity.type -notmatch 'SystemAssigned' -or -not $target.identity.principalId) {
        throw "Existing server '$TargetServer' has no system-assigned identity. Refusing to modify an existing server automatically."
    }

    $priorNativePreference = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    $geoJson = az sql db show `
        --resource-group $ResourceGroup `
        --server $TargetServer `
        --name $Database `
        --output json 2>$null
    $geoLookupExit = $LASTEXITCODE
    $PSNativeCommandUseErrorActionPreference = $priorNativePreference
    if ($geoLookupExit -eq 0) {
        $geo = $geoJson | ConvertFrom-Json
        if ($geo.sourceDatabaseId -ne $source.id -or $geo.secondaryType -ne 'Geo') {
            throw "Existing database '$Database' on '$TargetServer' is not the expected geo-replica of '$($source.id)'."
        }
    } elseif ($geoLookupExit -ne 3) {
        throw "Could not determine whether target database '$Database' exists; Azure CLI exited with code $geoLookupExit."
    }
}

Write-Host '--- Hyperscale geo-replica plan ---'
Write-Host "Subscription       : $($account.name) ($($account.id))"
Write-Host "Resource group     : $ResourceGroup"
Write-Host "Source             : $Database @ $SourceServer ($($source.location))"
Write-Host "Target server      : $TargetServer ($TargetLocation)"
Write-Host "Target server state: $(if ($target) { 'exists and validated' } else { 'create new' })"
Write-Host "Target identity    : system assigned"
Write-Host "Target auth        : Microsoft Entra only"
Write-Host "Target Entra admin : $($signedInUser.userPrincipalName) [User]"
Write-Host "Geo-replica state  : $(if ($geo) { 'already exists and validated' } else { 'create new' })"
Write-Host "Service objective  : $($source.currentServiceObjectiveName)"
Write-Host "Source HA replicas : $($source.highAvailabilityReplicaCount)"
Write-Host "Target HA replicas : $targetHaReplicas"
Write-Host "Source zone redundant: $($source.zoneRedundant)"
Write-Host "Target zone redundant: $targetZoneRedundant"
Write-Host "Backup redundancy  : $backupRedundancy"
Write-Host "Source TDE protector: $($sourceProtector.serverKeyType)"
if ($usesCustomerManagedKey) {
    $authorizationModel = if ($protectorVault.properties.enableRbacAuthorization) { 'Azure RBAC' } else { 'vault access policy' }
    Write-Host "Protector key       : $protectorKeyId"
    Write-Host "Key Vault auth      : $authorizationModel"
    Write-Host "CMK prerequisite    : grant target identity key access and register the protector key"
} else {
    Write-Host 'CMK prerequisite    : not required'
}
Write-Host 'Replication        : asynchronous; source commits do not wait for the geo-secondary'

if (-not $Execute) {
    Write-Host ''
    Write-Host 'PREVIEW ONLY. This creates a billable logical server and geo-replica. Rerun with -Execute after approval.' -ForegroundColor Yellow
    return
}

if (-not $target) {
    Write-Host ''
    Write-Host "--- Creating target logical server: $TargetServer ---"
    az sql server create `
        --resource-group $ResourceGroup `
        --name $TargetServer `
        --location $TargetLocation `
        --assign-identity `
        --identity-type SystemAssigned `
        --enable-ad-only-auth `
        --external-admin-principal-type User `
        --external-admin-name $signedInUser.userPrincipalName `
        --external-admin-sid $signedInUser.id `
        --minimal-tls-version 1.2 `
        --enable-public-network true `
        --tags environment=sandbox application=ward-general-ehr example=ha-resiliency-geo-replica criticality=low dataClassification=nonproduction `
        --output none

    $target = az sql server show `
        --resource-group $ResourceGroup `
        --name $TargetServer `
        --output json | ConvertFrom-Json
    if ($target.identity.type -notmatch 'SystemAssigned' -or -not $target.identity.principalId) {
        throw "Target server '$TargetServer' was created without the required system-assigned identity."
    }
    Write-Host "TargetServerCreated=$TargetServer"
    Write-Host "TargetServerPrincipalId=$($target.identity.principalId)"
}

if ($geo) {
    Write-Host "GeoReplicaAlreadyExists=$Database@$TargetServer"
    return
}

if ($usesCustomerManagedKey) {
    Write-Host ''
    Write-Host "--- Preparing target for source TDE protector: $protectorKeyId ---"
    if ($protectorVault.properties.enableRbacAuthorization) {
        $vaultScope = $protectorVault.id
        $roleName = 'Key Vault Crypto Service Encryption User'
        $roleAssignments = @(az role assignment list `
            --assignee-object-id $target.identity.principalId `
            --scope $vaultScope `
            --query "[?roleDefinitionName=='$roleName']" `
            --output json | ConvertFrom-Json)
        if ($roleAssignments.Count -eq 0) {
            az role assignment create `
                --assignee-object-id $target.identity.principalId `
                --assignee-principal-type ServicePrincipal `
                --role $roleName `
                --scope $vaultScope `
                --output none
        }
    } else {
        az keyvault set-policy `
            --name $protectorVaultName `
            --object-id $target.identity.principalId `
            --key-permissions get wrapKey unwrapKey `
            --output none
    }

    $registeredKeys = @(az sql server key list `
        --resource-group $ResourceGroup `
        --server $TargetServer `
        --output json | ConvertFrom-Json)
    $protectorRegistered = @($registeredKeys | Where-Object {
        if (-not $_.uri) { return $false }
        $registeredKeyId = $_.uri.TrimEnd('/')
        $expectedKeyId = $protectorKeyId.TrimEnd('/')
        $registeredKeyId -eq $expectedKeyId -or
            ($sourceProtector.autoRotationEnabled -and $registeredKeyId.StartsWith("$expectedKeyId/"))
    }).Count -gt 0
    if (-not $protectorRegistered) {
        az sql server key create `
            --resource-group $ResourceGroup `
            --server $TargetServer `
            --kid $protectorKeyId `
            --output none
    }

    $registeredKeys = @(az sql server key list `
        --resource-group $ResourceGroup `
        --server $TargetServer `
        --output json | ConvertFrom-Json)
    $protectorRegistered = @($registeredKeys | Where-Object {
        if (-not $_.uri) { return $false }
        $registeredKeyId = $_.uri.TrimEnd('/')
        $expectedKeyId = $protectorKeyId.TrimEnd('/')
        $registeredKeyId -eq $expectedKeyId -or
            ($sourceProtector.autoRotationEnabled -and $registeredKeyId.StartsWith("$expectedKeyId/"))
    }).Count -gt 0
    if (-not $protectorRegistered) {
        throw "Target server '$TargetServer' did not register TDE protector key '$protectorKeyId'."
    }
    Write-Host "TargetCmkAccessConfigured=$protectorVaultName"
    Write-Host "TargetProtectorKeyRegistered=$protectorKeyId"
}

Write-Host ''
Write-Host "--- Creating geo-replica: $Database @ $TargetServer ---"
az sql db replica create `
    --resource-group $ResourceGroup `
    --server $SourceServer `
    --name $Database `
    --partner-resource-group $ResourceGroup `
    --partner-server $TargetServer `
    --partner-database $Database `
    --secondary-type Geo `
    --service-objective $source.currentServiceObjectiveName `
    --ha-replicas $targetHaReplicas `
    --zone-redundant $targetZoneRedundant `
    --backup-storage-redundancy $backupRedundancy `
    --output none

Write-Host "GeoReplicaSubmitted=$Database@$TargetServer"
Write-Host 'Creation is asynchronous. Run ./verify-geo-replica.ps1 after Azure reports the database Online.'