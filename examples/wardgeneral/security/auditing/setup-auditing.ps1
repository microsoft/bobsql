<#
.SYNOPSIS
    Enable Security Azure SQL Database auditing to Log Analytics.

.DESCRIPTION
    Creates a dedicated, tagged Log Analytics workspace and configures the
    Ward General logical server audit policy to send SQLSecurityAuditEvents to
    it. The script refuses to replace an existing audit configuration.

    Log ingestion and retention are billable. Use only in a learning
    environment and run teardown-auditing.ps1 when finished.
#>
#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string] $ResourceGroup = ($env:RG ?? 'rg-collierhealth'),
    [string] $WorkspaceName,
    [string] $Location,
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
$actions = @(
    'BATCH_COMPLETED_GROUP',
    'SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP',
    'FAILED_DATABASE_AUTHENTICATION_GROUP'
)

try {
    az account show --query id -o tsv | Out-Null
}
catch {
    throw "Not signed in to Azure. Run 'az login', then run this script again."
}

$databaseResource = az sql db show `
    --resource-group $ResourceGroup `
    --server $serverName `
    --name $Database `
    --query '{id:id,location:location}' `
    -o json | ConvertFrom-Json
if (-not $Location) { $Location = $databaseResource.location }
$serverResourceId = $databaseResource.id -replace '/databases/[^/]+$', ''
$masterResourceId = "$serverResourceId/databases/master"

$workspace = az monitor log-analytics workspace list `
    --resource-group $ResourceGroup `
    --query "[?name=='$WorkspaceName'] | [0].{id:id,name:name,tags:tags,customerId:customerId}" `
    -o json | ConvertFrom-Json

if ($workspace) {
    $ownerTag = $workspace.tags.PSObject.Properties['wardgeneral']?.Value
    if ($ownerTag -ne 'security-auditing') {
        throw "Workspace '$WorkspaceName' exists without the Security ownership tag. Refusing to reuse it."
    }
    Write-Host "Workspace '$WorkspaceName' already exists — left in place." -ForegroundColor Yellow
}

$policy = az sql server audit-policy show `
    --resource-group $ResourceGroup `
    --name $serverName `
    --query '{state:state,logAnalyticsTarget:isAzureMonitorTargetEnabled,workspace:logAnalyticsWorkspaceResourceId,storageEndpoint:storageEndpoint,eventHub:eventHubAuthorizationRuleResourceId}' `
    -o json | ConvertFrom-Json
$usesThisWorkspace = $workspace -and
    $policy.logAnalyticsTarget -and
    $policy.workspace -ieq $workspace.id
$hasOtherTarget = -not [string]::IsNullOrWhiteSpace($policy.storageEndpoint) -or
    -not [string]::IsNullOrWhiteSpace($policy.eventHub)

if ($policy.state -eq 'Enabled' -and (-not $usesThisWorkspace -or $hasOtherTarget)) {
    throw 'An audit policy is already enabled with another destination. Refusing to replace or combine with it.'
}

if (-not $workspace -and $PSCmdlet.ShouldProcess(
    "$ResourceGroup/$WorkspaceName",
    'Create dedicated Log Analytics workspace with 30-day retention'
)) {
    $workspace = az monitor log-analytics workspace create `
        --resource-group $ResourceGroup `
        --workspace-name $WorkspaceName `
        --location $Location `
        --sku PerGB2018 `
        --retention-time 30 `
        --tags wardgeneral=security-auditing `
        --query '{id:id,name:name,tags:tags,customerId:customerId}' `
        -o json | ConvertFrom-Json
}

if ($WhatIfPreference) {
    $workspaceTarget = if ($workspace) { $workspace.id } else { "$ResourceGroup/$WorkspaceName (new workspace)" }
    $PSCmdlet.ShouldProcess(
        "$ResourceGroup/$serverName",
        "Enable Azure SQL Database auditing to $workspaceTarget with actions $($actions -join ', ')"
    ) | Out-Null
    Write-Host 'WhatIf complete. No workspace was created and no auditing policy was changed.' -ForegroundColor Green
    return
}
if (-not $workspace) { throw 'The Log Analytics workspace was not created or resolved.' }

$usesThisWorkspace = $policy.logAnalyticsTarget -and
    $policy.workspace -ieq $workspace.id

if ($usesThisWorkspace -and $policy.state -eq 'Enabled') {
    Write-Host 'The server audit policy already targets the Security workspace — left in place.' -ForegroundColor Yellow
}
elseif ($PSCmdlet.ShouldProcess(
    "$ResourceGroup/$serverName",
    "Enable Azure SQL Database auditing to $WorkspaceName"
)) {
    az sql server audit-policy update `
        --resource-group $ResourceGroup `
        --name $serverName `
        --state Enabled `
        --lats Enabled `
        --lawri $workspace.id `
        --actions $actions `
        -o none
}

$settingsUri = "https://management.azure.com$masterResourceId/providers/microsoft.insights/diagnosticSettings?api-version=2021-05-01-preview"
$diagnosticSettings = az rest --method get --url $settingsUri -o json | ConvertFrom-Json
$auditRoutes = @($diagnosticSettings.value | Where-Object {
    $_.properties.workspaceId -ieq $workspace.id -and
    @($_.properties.logs | Where-Object {
        $_.category -eq 'SQLSecurityAuditEvents' -and $_.enabled
    }).Count -eq 1
})
if ($auditRoutes.Count -ne 1) {
    throw "Expected exactly one enabled SQLSecurityAuditEvents route from master to '$WorkspaceName'; found $($auditRoutes.Count)."
}

Write-Host ''
Write-Host 'Security Azure SQL Database auditing is configured.' -ForegroundColor Green
Write-Host "Server    : $serverName" -ForegroundColor Gray
Write-Host "Database  : $Database" -ForegroundColor Gray
Write-Host "Workspace : $($workspace.id)" -ForegroundColor Gray
Write-Host 'Retention : 30 days' -ForegroundColor Gray
Write-Host "Actions   : $($actions -join ', ')" -ForegroundColor Gray
Write-Host "Route     : $($auditRoutes[0].name) on master" -ForegroundColor Gray
Write-Host "AuditStartUtc : $([datetime]::UtcNow.ToString('o'))" -ForegroundColor Cyan
Write-Host ''
Write-Host 'Auditing is ready. Log ingestion is billable and asynchronous.' -ForegroundColor Yellow
Write-Host 'Now run Ward General, open the unit board and one patient chart, then return to the audit skill.' -ForegroundColor Yellow
