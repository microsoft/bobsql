<#
.SYNOPSIS
    The "clean" option for the AZURE side of AI-Ready SQL -- deletes what
    deploy-ai.ps1 created, so it can be run again from scratch.

.DESCRIPTION
    reset-ai-objects.sql removes AI-Ready SQL's database objects. This removes the
    Azure resources underneath them. They are separate scripts because they fail
    for different reasons and cost different amounts to rebuild, and because most
    readers who need one do not need the other.

    Run this ONLY if you want to rebuild. deploy-ai.ps1 is idempotent -- a re-run
    against a healthy environment creates nothing and costs nothing -- so if your
    goal is "make sure everything is there", just run deploy-ai.ps1 again. This
    script is for the case where something is wrong at the resource level and
    skipping past it is no longer good enough.

    WHAT IT DELETES, in reverse dependency order
        Role assignment   SQL server identity -> Cognitive Services OpenAI User
        Role assignment   APIM identity       -> Cognitive Services User
        APIM instance     <AiResourceName>-gateway        (then purges it)
        Content Safety    <AiResourceName>-contentsafety  (then purges it)
        Foundry account   <AiResourceName>                (then purges it)

        The gpt-5 and text-embedding-3-large deployments are child resources of
        the Foundry account and go with it. They are not deleted separately.

        Role assignments are removed FIRST, while their scopes still exist. Delete
        the scope first and the assignment is left behind pointing at nothing.

    WHAT IT WILL NOT TOUCH
        The resource group, the logical server and the wardgeneral database.
        Those are Getting Started's, they are SHARED by every area in this project, and
        nothing here is worth losing them over.

        The server's system-assigned managed identity, unless you pass
        -RemoveServerIdentity. Other areas authenticate with it.

    SOFT DELETE IS THE PART THAT BITES. Both Azure AI Services accounts and APIM
    instances are soft-deleted, not removed. The name stays taken, so a rebuild
    with the SAME name fails or silently recovers the old resource with its old
    configuration -- which is the confusing outcome, because it looks like your
    fix did not apply. This script therefore purges each one after deleting it.
    Purging is irreversible and there is no undo, which is the point.

    Purge needs the region, and the region is only readable while the resource
    still exists, so it is captured BEFORE each delete.

    TIME. Deleting is quick. REBUILDING is not: a fresh APIM StandardV2 provision
    is ~30-45 minutes and is billable. If APIM is the only thing you are unhappy
    with, deploy-ai.ps1 -Force already recreates just that.

    All data is synthetic. No real PHI.

.PARAMETER SqlServerName
    Short name of the logical server (not the FQDN) whose identity holds the role
    assignment. Defaults to $env:SRV.

.PARAMETER ResourceGroup
    Resource group holding the resources. Defaults to $env:RG.

.PARAMETER AiResourceName
    The Microsoft Foundry (Azure OpenAI) account name. Every other name is
    derived from it unless you override it. Defaults to $env:AI_RESOURCE.

.PARAMETER ApimName
    Defaults to <AiResourceName>-gateway, matching deploy-ai.ps1.

.PARAMETER CsResourceName
    Defaults to <AiResourceName>-contentsafety, matching deploy-ai.ps1. Pass the
    real name if yours differs, or this script will report "not found" and leave
    a resource you meant to delete quietly running.

.PARAMETER SubscriptionId
    Optional. Defaults to $env:SUBSCRIPTION_ID, then whatever `az` is set to.

.PARAMETER KeepFoundry
    Delete the gateway and content safety but keep the Foundry account, its
    deployments and the embedding model behind them. Use this when the gateway
    is the broken part -- it avoids re-embedding the corpus later.

.PARAMETER RemoveServerIdentity
    Also turn off the logical server's system-assigned managed identity. Off by
    default because it is shared. Only meaningful if you are tearing the whole
    project environment down.

.PARAMETER NoPurge
    Delete but do not purge, leaving the resources recoverable. The names stay
    taken, so a rebuild under the same names will not behave as if it were new.

.EXAMPLE
    .\reset-ai-azure.ps1 -SqlServerName mysqlserver -ResourceGroup rg-mine ``
        -AiResourceName my-foundry -WhatIf
    Lists exactly what would be deleted and deletes nothing. Always start here.

.EXAMPLE
    .\reset-ai-azure.ps1 -SqlServerName mysqlserver -ResourceGroup rg-mine ``
        -AiResourceName my-foundry
    Prompts before each deletion, then removes everything above.

.EXAMPLE
    .\reset-ai-azure.ps1 -SqlServerName mysqlserver -ResourceGroup rg-mine ``
        -AiResourceName my-foundry -KeepFoundry
    Rebuild the gateway only. The embeddings in the database stay valid, because
    the model they were generated from is untouched.
#>
#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string] $SqlServerName  = ($env:SRV ?? ''),
    [string] $ResourceGroup  = ($env:RG ?? ''),
    [string] $AiResourceName = ($env:AI_RESOURCE ?? ''),
    [string] $ApimName       = '',
    [string] $CsResourceName = ($env:CS_RESOURCE ?? ''),
    [string] $SubscriptionId = ($env:SUBSCRIPTION_ID ?? ''),
    [switch] $KeepFoundry,
    [switch] $RemoveServerIdentity,
    [switch] $NoPurge
)

$ErrorActionPreference = 'Stop'

if (-not $ResourceGroup)  { throw 'Pass -ResourceGroup (or set $env:RG).' }
if (-not $AiResourceName) { throw 'Pass -AiResourceName (or set $env:AI_RESOURCE).' }

# Same derivation as deploy-ai.ps1 / azureaideploy.ps1. If these do not match
# your environment, the script reports "not found" and leaves the real resource
# alone -- which is the safe failure, but it is still a failure. Check the names
# in the banner below before answering yes to anything.
if (-not $ApimName)       { $ApimName       = "$AiResourceName-gateway" }
if (-not $CsResourceName) { $CsResourceName = "$AiResourceName-contentsafety" }

if ($SubscriptionId) { az account set --subscription $SubscriptionId --output none }
$subId = az account show --query id -o tsv

# Helper: az returns a non-zero exit code AND an empty string for "not found",
# but its exit code is unreliable enough elsewhere in this area that emptiness
# is what we test. 2>$null keeps expected not-found noise off the console.
# The parameter is AzArgs, not Args: $Args is an automatic variable, and shadowing
# it inside a function is the kind of thing that parses cleanly and misbehaves.
function Get-AzValue([string[]] $AzArgs) {
    $v = (& az @AzArgs 2>$null | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($v)) { return $null }
    return $v
}

Write-Host ''
Write-Host '=== AI-Ready SQL Azure reset ===' -ForegroundColor Cyan
Write-Host "  Subscription   : $subId"
Write-Host "  Resource group : $ResourceGroup"
Write-Host "  Foundry        : $AiResourceName$(if ($KeepFoundry) { '   (KEEPING - -KeepFoundry)' })"
Write-Host "  Content Safety : $CsResourceName"
Write-Host "  APIM gateway   : $ApimName"
Write-Host "  SQL server     : $(if ($SqlServerName) { $SqlServerName } else { '(not given - role assignment step skipped)' })"
Write-Host "  Purge after delete : $(if ($NoPurge) { 'NO  - names stay taken' } else { 'yes - irreversible' })"
Write-Host ''
Write-Host 'The resource group, the logical server and the wardgeneral database are NOT touched.' -ForegroundColor Gray
Write-Host ''

# ---- 1. Role assignments -------------------------------------------------
# First, while the scopes they point at still exist.
$aiId = Get-AzValue @('cognitiveservices', 'account', 'show', '-n', $AiResourceName, '-g', $ResourceGroup, '--query', 'id', '-o', 'tsv')
$csId = Get-AzValue @('cognitiveservices', 'account', 'show', '-n', $CsResourceName, '-g', $ResourceGroup, '--query', 'id', '-o', 'tsv')

Write-Host '[1] Role assignments...' -ForegroundColor Yellow

if ($SqlServerName -and $aiId) {
    $sqlMi = Get-AzValue @('sql', 'server', 'show', '-n', $SqlServerName, '-g', $ResourceGroup, '--query', 'identity.principalId', '-o', 'tsv')
    if ($sqlMi) {
        if ($PSCmdlet.ShouldProcess("$sqlMi -> Cognitive Services OpenAI User on $AiResourceName", 'Remove role assignment')) {
            az role assignment delete --assignee $sqlMi --role 'Cognitive Services OpenAI User' --scope $aiId --output none 2>$null
            Write-Host '    removed: SQL identity -> Cognitive Services OpenAI User'
        }
    }
    else { Write-Host '    SQL server has no managed identity - nothing to remove.' -ForegroundColor Gray }
}
else { Write-Host '    skipped (no -SqlServerName, or the Foundry account is already gone).' -ForegroundColor Gray }

if ($csId) {
    $apimMi = Get-AzValue @('apim', 'show', '-n', $ApimName, '-g', $ResourceGroup, '--query', 'identity.principalId', '-o', 'tsv')
    if ($apimMi) {
        if ($PSCmdlet.ShouldProcess("$apimMi -> Cognitive Services User on $CsResourceName", 'Remove role assignment')) {
            az role assignment delete --assignee $apimMi --role 'Cognitive Services User' --scope $csId --output none 2>$null
            Write-Host '    removed: APIM identity -> Cognitive Services User'
        }
    }
    else { Write-Host '    APIM not found or has no identity - nothing to remove.' -ForegroundColor Gray }
}

# ---- 2. APIM gateway -----------------------------------------------------
# Capture the region BEFORE deleting: purge needs it, and after the delete it is
# no longer readable from the resource.
Write-Host '[2] APIM gateway...' -ForegroundColor Yellow
$apimLoc = Get-AzValue @('apim', 'show', '-n', $ApimName, '-g', $ResourceGroup, '--query', 'location', '-o', 'tsv')

if ($apimLoc) {
    if ($PSCmdlet.ShouldProcess("$ApimName ($apimLoc)", 'Delete APIM instance')) {
        az apim delete -n $ApimName -g $ResourceGroup --yes --output none
        Write-Host "    deleted $ApimName"

        if (-not $NoPurge) {
            # Soft-deleted APIM keeps the name reserved. Purge frees it.
            az apim deletedservice purge --service-name $ApimName --location $apimLoc --output none 2>$null
            Write-Host '    purged (name released).'
        }
    }
}
else { Write-Host "    $ApimName not found - nothing to delete." -ForegroundColor Gray }

# ---- 3. Content Safety ---------------------------------------------------
Write-Host '[3] Content Safety...' -ForegroundColor Yellow
$csLoc = Get-AzValue @('cognitiveservices', 'account', 'show', '-n', $CsResourceName, '-g', $ResourceGroup, '--query', 'location', '-o', 'tsv')

if ($csLoc) {
    if ($PSCmdlet.ShouldProcess("$CsResourceName ($csLoc)", 'Delete Content Safety account')) {
        az cognitiveservices account delete -n $CsResourceName -g $ResourceGroup --output none
        Write-Host "    deleted $CsResourceName"

        if (-not $NoPurge) {
            az cognitiveservices account purge -n $CsResourceName -g $ResourceGroup -l $csLoc --output none 2>$null
            Write-Host '    purged (name released).'
        }
    }
}
else { Write-Host "    $CsResourceName not found - nothing to delete." -ForegroundColor Gray }

# ---- 4. Foundry account + its deployments --------------------------------
Write-Host '[4] Foundry account...' -ForegroundColor Yellow

if ($KeepFoundry) {
    Write-Host '    kept (-KeepFoundry). The embedding model is intact, so the vectors' -ForegroundColor Gray
    Write-Host '    already in the database remain valid and do not need regenerating.' -ForegroundColor Gray
}
elseif ($aiId) {
    $aiLoc = Get-AzValue @('cognitiveservices', 'account', 'show', '-n', $AiResourceName, '-g', $ResourceGroup, '--query', 'location', '-o', 'tsv')

    Write-Host '    NOTE: deleting this invalidates nothing in the database by itself, but' -ForegroundColor Yellow
    Write-Host '    a rebuilt account is a new model instance. Re-run reset-ai-objects.sql' -ForegroundColor Yellow
    Write-Host '    and 06 if you want vectors regenerated against it.' -ForegroundColor Yellow

    if ($PSCmdlet.ShouldProcess("$AiResourceName ($aiLoc), including the gpt-5 and text-embedding-3-large deployments", 'Delete Foundry account')) {
        az cognitiveservices account delete -n $AiResourceName -g $ResourceGroup --output none
        Write-Host "    deleted $AiResourceName"

        if (-not $NoPurge) {
            az cognitiveservices account purge -n $AiResourceName -g $ResourceGroup -l $aiLoc --output none 2>$null
            Write-Host '    purged (name released).'
        }
    }
}
else { Write-Host "    $AiResourceName not found - nothing to delete." -ForegroundColor Gray }

# ---- 5. Server managed identity (opt-in) ---------------------------------
Write-Host '[5] Logical server identity...' -ForegroundColor Yellow

if ($RemoveServerIdentity -and $SqlServerName) {
    if ($PSCmdlet.ShouldProcess($SqlServerName, 'Remove system-assigned managed identity')) {
        az sql server update -n $SqlServerName -g $ResourceGroup --identity-type None --output none
        Write-Host '    identity removed. Other areas that authenticate passwordlessly will'
        Write-Host '    need it back - deploy-ai.ps1 re-creates it.'
    }
}
else { Write-Host '    left in place (shared with other areas). Pass -RemoveServerIdentity to remove it.' -ForegroundColor Gray }

# ---- Done ----------------------------------------------------------------
Write-Host ''
Write-Host '=== Reset complete ===' -ForegroundColor Cyan
Write-Host ''
Write-Host 'To rebuild:' -ForegroundColor Green
Write-Host '  1. deploy-ai.ps1          - recreates the Azure resources.'
Write-Host '                              A fresh APIM StandardV2 is ~30-45 min and is billable.'
Write-Host '  2. reset-ai-objects.sql   - only if the Foundry account was deleted and you want the'
Write-Host '                              database objects rebuilt against the new one.'
Write-Host '  3. 06 -> 07 -> 08 -> 09   - in order. 06 re-embeds the corpus if you reset it, which'
Write-Host '                              is hours of metered calls. Check verify-embeddings.sql first.'
Write-Host ''
Write-Host 'If you kept the Foundry account, your vectors are still valid - do not run 06 from scratch.' -ForegroundColor Gray
