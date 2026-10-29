<#
.SYNOPSIS
    Remove the Security Azure SQL Database auditing destination and workspace.

.DESCRIPTION
    Disables auditing only when the current server policy points exclusively to
    the tagged Security workspace, then deletes that workspace. The script
    refuses to alter another audit configuration or delete an unowned workspace.
#>
#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string] $ResourceGroup = ($env:RG ?? 'rg-collierhealth'),
    [string] $WorkspaceName,
    [string] $Server,
    [string] $Database
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$here = $PSScriptRoot

$loadEnv = Join-Path $here '..' '..' 'first-app' 'load-env.ps1'
if (Test-Path $loadEnv) {
    $savedWhatIfPreference = $WhatIfPreference
    try {
        $WhatIfPreference = $false
        & $loadEnv -Optional -Quiet
    }
    finally {
        $WhatIfPreference = $savedWhatIfPreference
    }
}

if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
if (-not $WorkspaceName) { $WorkspaceName = "$Database-security-audit" }
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') {
    throw 'No server. Fill in WardGeneral__Server in first-app/wardgeneral.env, set the environment variable, or pass -Server explicitly.'
}
$serverName = ($Server -split '\.')[0]

$databaseResource = az sql db show `
    --resource-group $ResourceGroup `
    --server $serverName `
    --name $Database `
    --query '{id:id}' `
    -o json | ConvertFrom-Json
$serverResourceId = $databaseResource.id -replace '/databases/[^/]+$', ''
$masterResourceId = "$serverResourceId/databases/master"

$workspace = az monitor log-analytics workspace list `
    --resource-group $ResourceGroup `
    --query "[?name=='$WorkspaceName'] | [0].{id:id,name:name,tags:tags}" `
    -o json | ConvertFrom-Json
if (-not $workspace) {
    Write-Host "Workspace '$WorkspaceName' does not exist. Nothing to remove." -ForegroundColor Yellow
    return
}
$ownerTag = $workspace.tags.PSObject.Properties['wardgeneral']?.Value
if ($ownerTag -ne 'security-auditing') {
    throw "Workspace '$WorkspaceName' does not carry the Security ownership tag. Refusing to delete it."
}

$policy = az sql server audit-policy show `
    --resource-group $ResourceGroup `
    --name $serverName `
    --query '{state:state,logAnalyticsTarget:isAzureMonitorTargetEnabled,workspace:logAnalyticsWorkspaceResourceId,storageEndpoint:storageEndpoint,eventHub:eventHubAuthorizationRuleResourceId}' `
    -o json | ConvertFrom-Json
$usesThisWorkspace = $policy.logAnalyticsTarget -and
    $policy.workspace -ieq $workspace.id
$hasOtherTarget = -not [string]::IsNullOrWhiteSpace($policy.storageEndpoint) -or
    -not [string]::IsNullOrWhiteSpace($policy.eventHub)

if ($policy.logAnalyticsTarget -and -not $usesThisWorkspace) {
    throw 'The server audit policy points to another Log Analytics workspace. Refusing to alter it.'
}
if ($usesThisWorkspace -and $hasOtherTarget) {
    throw 'The server audit policy also has another destination. Refusing to disable the combined policy.'
}

$settingsUri = "https://management.azure.com$masterResourceId/providers/microsoft.insights/diagnosticSettings?api-version=2021-05-01-preview"
$diagnosticSettings = az rest --method get --url $settingsUri -o json | ConvertFrom-Json
$ownedRoutes = @($diagnosticSettings.value | Where-Object {
    $_.properties.workspaceId -ieq $workspace.id -and
    @($_.properties.logs | Where-Object {
        $_.category -eq 'SQLSecurityAuditEvents' -and $_.enabled
    }).Count -eq 1
})
foreach ($route in $ownedRoutes) {
    $otherEnabledLogs = @($route.properties.logs | Where-Object {
        $_.enabled -and $_.category -ne 'SQLSecurityAuditEvents'
    })
    $enabledMetrics = @($route.properties.metrics | Where-Object { $_.enabled })
    if ($otherEnabledLogs.Count -gt 0 -or $enabledMetrics.Count -gt 0) {
        throw "Diagnostic setting '$($route.name)' also carries non-audit data. Refusing to delete it."
    }
}

if ($usesThisWorkspace -and $PSCmdlet.ShouldProcess(
    "$ResourceGroup/$serverName",
    "Disable the audit policy targeting $WorkspaceName"
)) {
    az sql server audit-policy update `
        --resource-group $ResourceGroup `
        --name $serverName `
        --state Disabled `
        --lats Disabled `
        -o none
}

$remainingSettings = if ($WhatIfPreference) {
    $diagnosticSettings
}
else {
    az rest --method get --url $settingsUri -o json | ConvertFrom-Json
}
$remainingRouteNames = @($remainingSettings.value | ForEach-Object { $_.name })
foreach ($route in $ownedRoutes | Where-Object { $_.name -in $remainingRouteNames }) {
    if ($PSCmdlet.ShouldProcess(
        "$masterResourceId/$($route.name)",
        'Delete the generated SQLSecurityAuditEvents diagnostic setting'
    )) {
        az monitor diagnostic-settings delete `
            --name $route.name `
            --resource $masterResourceId
    }
}

if ($PSCmdlet.ShouldProcess(
    "$ResourceGroup/$WorkspaceName",
    'Delete the tagged Security Log Analytics workspace'
)) {
    az monitor log-analytics workspace delete `
        --resource-group $ResourceGroup `
        --workspace-name $WorkspaceName `
        --yes
}

if ($WhatIfPreference) {
    Write-Host 'WhatIf complete. No audit policy, diagnostic setting, or workspace was changed.' -ForegroundColor Green
    return
}

Write-Host 'Security audit resources were removed.' -ForegroundColor Green
