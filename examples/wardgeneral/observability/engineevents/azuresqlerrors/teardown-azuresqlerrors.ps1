<#
.SYNOPSIS
    Remove the Observability Azure SQL error-log diagnostic route and workspace.

.DESCRIPTION
    Loads the Ward General server and database from Ward General App configuration,
    resolves the exact Azure SQL database, removes only the diagnostic setting
    named observability-azuresqlerrors, and then deletes the dedicated Log Analytics
    workspace.

    The workspace must carry the tag wardgeneral=observability-engineevents. This
    guard prevents the script from deleting a shared or unrelated workspace.
    Use -AllowUntaggedWorkspace only after independently verifying ownership.

    Workspace deletion is recoverable by default. Use -PermanentlyDelete to
    bypass the recovery period and release the workspace name immediately.

.PARAMETER ResourceGroup
    Resource group containing the logical server and workspace. Defaults to RG,
    then rg-collierhealth.

.PARAMETER WorkspaceName
    Dedicated workspace name. Defaults to <database>-observability-logs.

.PARAMETER WorkspaceResourceId
    Optional exact workspace ARM resource ID. Overrides ResourceGroup and
    WorkspaceName for workspace lookup.

.PARAMETER DiagnosticSettingName
    Diagnostic setting to remove from the database. Defaults to
    observability-azuresqlerrors.

.PARAMETER PermanentlyDelete
    Permanently delete the workspace without the recovery period.

.PARAMETER AllowUntaggedWorkspace
    Allow deletion when the workspace lacks the ownership tag. Use only after
    verifying that the workspace is dedicated to this Observability example.

.EXAMPLE
    ./teardown-azuresqlerrors.ps1 -WhatIf

.EXAMPLE
    ./teardown-azuresqlerrors.ps1

.EXAMPLE
    ./teardown-azuresqlerrors.ps1 -PermanentlyDelete
#>
#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string] $ResourceGroup = ($env:RG ?? 'rg-collierhealth'),
    [string] $WorkspaceName,
    [string] $WorkspaceResourceId,
    [string] $DiagnosticSettingName = 'observability-azuresqlerrors',
    [switch] $PermanentlyDelete,
    [switch] $AllowUntaggedWorkspace,
    [string] $Server,
    [string] $Database
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$here = $PSScriptRoot

$loadEnv = Join-Path $here '..' '..' '..' 'first-app' 'load-env.ps1'
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
if (-not $WorkspaceName) { $WorkspaceName = "$Database-observability-logs" }
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') {
    throw 'No server. Fill in WardGeneral__Server in first-app/wardgeneral.env, set the environment variable, or pass -Server explicitly.'
}
$serverName = ($Server -split '\.')[0]

try {
    $subscription = az account show --query '{name:name,id:id}' -o json |
        ConvertFrom-Json
}
catch {
    throw "Not signed in to Azure. Run 'az login', then run this script again."
}

$databaseResource = az sql db show `
    --resource-group $ResourceGroup `
    --server $serverName `
    --name $Database `
    --query '{id:id}' `
    -o json | ConvertFrom-Json

$diagnosticSetting = @(
    az monitor diagnostic-settings list `
        --resource $databaseResource.id `
        --query "[?name=='$DiagnosticSettingName']" `
        -o json | ConvertFrom-Json
) | Select-Object -First 1

$workspace = $null
try {
    if ($WorkspaceResourceId) {
        $workspace = az monitor log-analytics workspace show `
            --ids $WorkspaceResourceId `
            --query '{id:id,name:name,resourceGroup:resourceGroup,tags:tags}' `
            -o json | ConvertFrom-Json
    }
    else {
        $workspace = az monitor log-analytics workspace list `
            --resource-group $ResourceGroup `
            --query "[?name=='$WorkspaceName'] | [0].{id:id,name:name,resourceGroup:resourceGroup,tags:tags}" `
            -o json | ConvertFrom-Json
    }
}
catch {
    $workspace = $null
}

Write-Host 'Observability — tear down retained Azure SQL engine errors' -ForegroundColor Cyan
Write-Host "Subscription       : $($subscription.name)  ($($subscription.id))" -ForegroundColor Gray
Write-Host "Database           : $serverName/$Database" -ForegroundColor Gray
Write-Host "Diagnostic setting : $DiagnosticSettingName" -ForegroundColor Gray
Write-Host "Workspace          : $(if ($workspace) { $workspace.id } else { 'not found' })" -ForegroundColor Gray
Write-Host ''

if ($workspace -and -not $AllowUntaggedWorkspace) {
    $ownerTag = $null
    if ($workspace.tags) {
        $tagProperty = $workspace.tags.PSObject.Properties['wardgeneral']
        if ($tagProperty) { $ownerTag = $tagProperty.Value }
    }
    if ($ownerTag -ne 'observability-engineevents') {
        throw @"
Refusing to delete workspace '$($workspace.name)' because it does not carry
wardgeneral=observability-engineevents. It might be shared or unrelated. Verify its
ownership, then pass -AllowUntaggedWorkspace only if deletion is intentional.
"@
    }
}

if ($diagnosticSetting) {
    if ($workspace -and $diagnosticSetting.workspaceId -and
        $diagnosticSetting.workspaceId -ine $workspace.id) {
        throw "Diagnostic setting '$DiagnosticSettingName' points to a different workspace. No resources were deleted."
    }

    if ($PSCmdlet.ShouldProcess(
        $databaseResource.id,
        "Delete diagnostic setting '$DiagnosticSettingName'"
    )) {
        az monitor diagnostic-settings delete `
            --name $DiagnosticSettingName `
            --resource $databaseResource.id
        Write-Host "Deleted diagnostic setting '$DiagnosticSettingName'." -ForegroundColor Green
    }
}
else {
    Write-Host "Diagnostic setting '$DiagnosticSettingName' was not found." -ForegroundColor Yellow
}

if ($workspace) {
    $deleteArguments = @(
        'monitor', 'log-analytics', 'workspace', 'delete',
        '--ids', $workspace.id,
        '--yes'
    )
    if ($PermanentlyDelete) { $deleteArguments += '--force' }

    $deleteMode = if ($PermanentlyDelete) { 'permanently delete' } else { 'delete' }
    if ($PSCmdlet.ShouldProcess($workspace.id, "$deleteMode Log Analytics workspace")) {
        az @deleteArguments
        Write-Host "Deleted workspace '$($workspace.name)'." -ForegroundColor Green
        if (-not $PermanentlyDelete) {
            Write-Host 'The workspace remains recoverable during the Azure recovery period.' -ForegroundColor Yellow
        }
    }
}
else {
    Write-Host "Workspace '$WorkspaceName' was not found." -ForegroundColor Yellow
}

if (-not $diagnosticSetting -and -not $workspace) {
    Write-Host 'Nothing to remove.' -ForegroundColor Green
}