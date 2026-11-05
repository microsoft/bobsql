<#
.SYNOPSIS
    Create the Observability Log Analytics path for retained Azure SQL errors.

.DESCRIPTION
    Loads Ward General configuration from Ward General App, creates a dedicated Log
    Analytics workspace, and creates a diagnostic setting on the configured
    Azure SQL database that routes the Errors category using the resource-
    specific destination schema.

    This enables billable log ingestion and retention. Use only in a learning
    environment. The script is idempotent and refuses to reuse an existing
    workspace that lacks the wardgeneral=observability-engineevents ownership tag.

.PARAMETER ResourceGroup
    Resource group containing the logical server and workspace. Defaults to RG,
    then rg-collierhealth.

.PARAMETER WorkspaceName
    Dedicated workspace name. Defaults to <database>-observability-logs.

.PARAMETER DiagnosticSettingName
    Diagnostic setting created on the database. Defaults to
    observability-azuresqlerrors.

.PARAMETER Location
    Workspace location. Defaults to the Azure SQL database location.

.EXAMPLE
    ./setup-azuresqlerrors.ps1 -WhatIf

.EXAMPLE
    ./setup-azuresqlerrors.ps1
#>
#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string] $ResourceGroup = ($env:RG ?? 'rg-collierhealth'),
    [string] $WorkspaceName,
    [string] $DiagnosticSettingName = 'observability-azuresqlerrors',
    [string] $Location,
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
    --query '{id:id,location:location}' `
    -o json | ConvertFrom-Json
if (-not $Location) { $Location = $databaseResource.location }

$categories = @(
    az monitor diagnostic-settings categories list `
        --resource $databaseResource.id `
        --query "value[?name=='Errors'].name" `
        -o tsv
)
if ($categories -notcontains 'Errors') {
    throw "The Errors diagnostic category is not available on $($databaseResource.id)."
}

$workspace = az monitor log-analytics workspace list `
    --resource-group $ResourceGroup `
    --query "[?name=='$WorkspaceName'] | [0].{id:id,name:name,resourceGroup:resourceGroup,tags:tags,customerId:customerId}" `
    -o json | ConvertFrom-Json

if ($workspace) {
    $ownerTag = $null
    if ($workspace.tags) {
        $tagProperty = $workspace.tags.PSObject.Properties['wardgeneral']
        if ($tagProperty) { $ownerTag = $tagProperty.Value }
    }
    if ($ownerTag -ne 'observability-engineevents') {
        throw "Workspace '$WorkspaceName' already exists without the Observability ownership tag. Refusing to reuse it."
    }
    Write-Host "Workspace '$WorkspaceName' already exists — left in place." -ForegroundColor Yellow
}
elseif ($PSCmdlet.ShouldProcess(
    "$ResourceGroup/$WorkspaceName",
    'Create dedicated Log Analytics workspace with 30-day retention'
)) {
    $workspace = az monitor log-analytics workspace create `
        --resource-group $ResourceGroup `
        --workspace-name $WorkspaceName `
        --location $Location `
        --retention-time 30 `
        --tags wardgeneral=observability-engineevents `
        --query '{id:id,name:name,resourceGroup:resourceGroup,tags:tags,customerId:customerId}' `
        -o json | ConvertFrom-Json
}

if ($WhatIfPreference) {
    Write-Host 'WhatIf complete. No workspace or diagnostic setting was created.' -ForegroundColor Green
    return
}

if (-not $workspace) {
    throw 'The Log Analytics workspace was not created or resolved.'
}

$managementToken = az account get-access-token `
    --resource https://management.azure.com/ `
    --query accessToken -o tsv
$settingId = "$($databaseResource.id)/providers/Microsoft.Insights/diagnosticSettings/$DiagnosticSettingName"
$settingUri = "https://management.azure.com${settingId}?api-version=2021-05-01-preview"
$existingSetting = $null
try {
    $existingSetting = Invoke-RestMethod `
        -Method Get `
        -Uri $settingUri `
        -Headers @{ Authorization = "Bearer $managementToken" }
}
catch {
    if (-not $_.Exception.Response -or
        [int]$_.Exception.Response.StatusCode -ne 404) {
        throw
    }
}

$settingIsCurrent = $existingSetting -and
    $existingSetting.properties.workspaceId -ieq $workspace.id -and
    $existingSetting.properties.logAnalyticsDestinationType -eq 'Dedicated' -and
    @($existingSetting.properties.logs | Where-Object {
        $_.enabled -and $_.category -eq 'Errors'
    }).Count -eq 1

if ($settingIsCurrent) {
    Write-Host "Diagnostic setting '$DiagnosticSettingName' already has the required configuration — left in place." -ForegroundColor Yellow
}
elseif ($PSCmdlet.ShouldProcess(
    $databaseResource.id,
    "Create or replace diagnostic setting '$DiagnosticSettingName' and enable billable Errors ingestion"
)) {
    $settingBody = @{
        properties = @{
            workspaceId = $workspace.id
            logAnalyticsDestinationType = 'Dedicated'
            logs = @(
                @{
                    category = 'Errors'
                    enabled = $true
                }
            )
        }
    } | ConvertTo-Json -Depth 6
    $existingSetting = Invoke-RestMethod `
        -Method Put `
        -Uri $settingUri `
        -Headers @{ Authorization = "Bearer $managementToken" } `
        -ContentType 'application/json' `
        -Body $settingBody
}

Write-Host ''
Write-Host 'Observability Azure SQL error collection is configured.' -ForegroundColor Green
Write-Host "Database           : $serverName/$Database" -ForegroundColor Gray
Write-Host "Workspace          : $($workspace.id)" -ForegroundColor Gray
Write-Host "Diagnostic setting : $DiagnosticSettingName" -ForegroundColor Gray
Write-Host 'Category           : Errors' -ForegroundColor Gray
Write-Host 'Destination schema : resource specific' -ForegroundColor Gray
Write-Host ''
Write-Host 'Log ingestion is billable and asynchronous. Use teardown-azuresqlerrors.ps1 when finished.' -ForegroundColor Yellow