<#
.SYNOPSIS
    Deploy the ENTIRE Azure AI layer for the Ward General Hyperscale demo in one
    command: the Microsoft Foundry (Azure OpenAI) resource + model deployments,
    the passwordless managed-identity wiring, RBAC, and the APIM AI gateway +
    content safety. The gateway is the DEFAULT path; -NoGateway opts out.

.DESCRIPTION
    This is the Azure control-plane orchestrator for the AI layer. It sits BETWEEN
    the database provision and the in-engine SQL objects:

        1. provision-hyperscale.ps1   (deploy-hyperscale)      — server + wardgeneral DB
        2. azureaideploy.ps1          (THIS)                    — Foundry + APIM + MIs + RBAC
        3. DB objects, run BY THE READER: sql/06 → 07 → 08 → 09

    What it does (all idempotent — "create if absent"; safe to re-run):
      - Foundry (Azure OpenAI) account named by -AiResourceName (kind=OpenAI,
        custom subdomain — required for Entra token auth). Created only if missing.
      - Model deployments: `gpt-5` and `text-embedding-3-large`, both
        GlobalStandard at capacity 100 (pinned so a fresh deploy never needs a
        manual TPM bump).
      - The wardgeneral server's SYSTEM-ASSIGNED MANAGED IDENTITY (assigned if
        absent) — the keyless caller for both the direct Foundry path and the
        gateway path.
      - RBAC: server MI -> "Cognitive Services OpenAI User" on the Foundry account.
      - Delegates to setup-ai-gateway.ps1 — APIM StandardV2 + its own MI + a
        validate-azure-ad-token policy (accepts ONLY the server MI on the
        first-party Cognitive Services audience — no app registration) — then to
        add-content-safety.ps1 for input/output moderation. Suppress with
        -NoGateway / -NoContentSafety.

    What it does NOT do (deliberate — different owners / different lifecycles):
      - It does NOT create the resource group, the SQL server, or the database
        (that is provision-hyperscale.ps1 / deploy-hyperscale; the DB is
        SHARED across areas — never recreated here).
      - It does NOT run the in-engine SQL (06/07/08/09) or build embeddings.
        Those reference the resources created here and run AFTER (see the
        printed next steps). The reader runs them in the tool of their choice —
        MSSQL extension, SSMS, ADS or sqlcmd — because in AI-Ready SQL the T-SQL is
        the lesson. 06 both creates the vector objects and embeds the corpus.

    Cost/time: model deployments + RBAC are quick. The gateway adds a real,
    always-on APIM StandardV2 (~30-45 min to provision, billable) — that is what
    -NoGateway is there to skip.

.PARAMETER ResourceGroup
    Resource group holding the SQL server. No default -- $env:RG or pass it.

.PARAMETER AiResourceName
    Globally unique name for the Foundry account (becomes
    <name>.openai.azure.com). No default -- $env:AI_RESOURCE or pass it. This is
    the value that replaces <your-foundry> in 06 and 08.

.PARAMETER SqlServerName
    Short name of the logical server whose managed identity gets the role.
    No default -- $env:SRV or pass it.

.PARAMETER ApimName
    Name for the APIM instance. Defaults to <AiResourceName>-gateway. Ignored
    with -NoGateway.

.PARAMETER CsResourceName
    Name for the Content Safety resource. Defaults to
    <AiResourceName>-contentsafety.

.PARAMETER PublisherEmail
    APIM publisher contact. Required unless -NoGateway. $env:PUBLISHER_EMAIL.

.PARAMETER NoGateway
    Skip the APIM AI gateway and content safety entirely. The database then calls
    the model deployment directly, and 08-ai-assistance.sql needs its @UseGateway
    default changed from 1 to 0 (the script says where). To reverse this later,
    put the default back to 1 and re-run 08 -- it is CREATE OR ALTER.

.PARAMETER NoContentSafety
    Provision the gateway but skip the content-safety resource and its policy.

.PARAMETER SkipModels
    Skip Foundry account + model deployment (assume they already exist); still do
    the MI + RBAC (+ optional gateway).

.PARAMETER Force
    Passed through to setup-ai-gateway.ps1 (recreate APIM from scratch).

.EXAMPLE
    # The default: Foundry + models + MI + RBAC + APIM gateway + content safety
    .\azureaideploy.ps1 -ResourceGroup rg-mine -AiResourceName my-foundry ``
        -SqlServerName my-sql-server -PublisherEmail me@example.com

.EXAMPLE
    # Direct-to-model only — no APIM, nothing always-on and billable
    .\azureaideploy.ps1 -ResourceGroup rg-mine -AiResourceName my-foundry ``
        -SqlServerName my-sql-server -NoGateway
#>
[CmdletBinding()]
param(
    # Defaults to whatever subscription `az account show` reports, so a reader who
    # has already run `az login` needs to set nothing. Override with SUBSCRIPTION_ID.
    [string] $SubscriptionId    = ($env:SUBSCRIPTION_ID ?? ''),
    # No default resource or server names: a default here is the AUTHOR's
    # environment, and a reader who forgets a switch would silently aim at it.
    # Set them per-shell (RG / AI_RESOURCE / SRV) or pass them explicitly.
    [string] $ResourceGroup     = ($env:RG ?? ''),
    [string] $AiResourceName    = ($env:AI_RESOURCE ?? ''),
    [string] $AiLocation        = ($env:AI_LOCATION ?? 'eastus2'),
    [string] $SqlServerName     = ($env:SRV ?? ''),
    # Gateway naming. Both default to a name DERIVED from your Foundry resource,
    # so there is still nothing of anyone else's baked in. Only used with -Gateway.
    [string] $ApimName          = '',
    [string] $CsResourceName    = '',
    # APIM requires a publisher contact. Required unless -NoGateway.
    [string] $PublisherEmail    = ($env:PUBLISHER_EMAIL ?? ''),
    [int]    $ChatCapacity      = 100,
    [int]    $EmbeddingCapacity = 100,
    # Opt-OUT, not opt-in: the governed path is the one the area teaches, so a
    # bare run gives you the gateway. Skipping it is the deliberate act.
    [switch] $NoGateway,
    [switch] $NoContentSafety,
    [switch] $SkipModels,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Gateway       = -not $NoGateway
$ContentSafety = $Gateway -and -not $NoContentSafety   # it attaches to the gateway policy

# Fail here, not forty lines into an az call whose error message names a resource
# group the reader has never heard of.
$missing = @()
if (-not $ResourceGroup)  { $missing += '-ResourceGroup  (or $env:RG)' }
if (-not $AiResourceName) { $missing += '-AiResourceName (or $env:AI_RESOURCE)' }
if (-not $SqlServerName)  { $missing += '-SqlServerName  (or $env:SRV)' }
if ($missing.Count -gt 0) {
    throw "Missing required name(s):`n  $($missing -join "`n  ")`n" +
          "These have no defaults on purpose - a default would be someone else's environment."
}

if (-not $ApimName)       { $ApimName       = "$AiResourceName-gateway" }
if (-not $CsResourceName) { $CsResourceName = "$AiResourceName-contentsafety" }
if ($Gateway -and -not $PublisherEmail) {
    throw "The gateway needs -PublisherEmail (or `$env:PUBLISHER_EMAIL). APIM requires a publisher contact for service notifications. Pass -NoGateway to skip the gateway instead."
}

function Set-ModelDeployment {
    param([string]$Name, [string]$ModelName, [int]$Capacity)
    $have = az cognitiveservices account deployment list -n $AiResourceName -g $ResourceGroup --query "[?name=='$Name'].name" -o tsv 2>$null
    if ($have) {
        Write-Host "  Deployment '$Name' exists." -ForegroundColor Green
        return
    }
    Write-Host "  Creating deployment '$Name' ($ModelName, GlobalStandard capacity $Capacity)..." -ForegroundColor Gray
    az cognitiveservices account deployment create -n $AiResourceName -g $ResourceGroup `
        --deployment-name $Name --model-name $ModelName `
        --model-version 1 --model-format OpenAI `
        --sku-name GlobalStandard --sku-capacity $Capacity --output none
    if ($LASTEXITCODE -ne 0) { throw "Failed to create deployment '$Name'." }
    Write-Host "  Deployment '$Name' created." -ForegroundColor Green
}

Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ' Ward General — Azure AI layer deploy'         -ForegroundColor Cyan
Write-Host "  Foundry : $AiResourceName ($AiLocation)"     -ForegroundColor Gray
Write-Host "  SQL MI  : $SqlServerName"                    -ForegroundColor Gray
Write-Host "  Gateway : $([bool]$Gateway)  ContentSafety: $([bool]$ContentSafety)" -ForegroundColor Gray
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ''

# ── 1. Subscription ──
Write-Host '[1] Subscription...' -ForegroundColor Yellow
if ($SubscriptionId) {
    az account set --subscription $SubscriptionId
    if ($LASTEXITCODE -ne 0) { Write-Host "  ERROR: could not select subscription '$SubscriptionId'. Run 'az login' first." -ForegroundColor Red; exit 1 }
} else {
    $SubscriptionId = az account show --query id -o tsv 2>$null
    if (-not $SubscriptionId) { Write-Host "  ERROR: not signed in. Run 'az login' (or set SUBSCRIPTION_ID)." -ForegroundColor Red; exit 1 }
}
Write-Host "  OK - $(az account show --query name -o tsv) ($SubscriptionId)" -ForegroundColor Green
Write-Host ''

# ── 2. Foundry account + model deployments ──
if ($SkipModels) {
    Write-Host '[2] Skipping Foundry account + models (-SkipModels).' -ForegroundColor Yellow
} else {
    Write-Host '[2] Foundry (Azure OpenAI) account + models...' -ForegroundColor Yellow
    $acct = az cognitiveservices account show -n $AiResourceName -g $ResourceGroup --query name -o tsv 2>$null
    if (-not $acct) {
        Write-Host "  Creating Foundry account '$AiResourceName' (kind=OpenAI, S0, custom subdomain)..." -ForegroundColor Gray
        az cognitiveservices account create -n $AiResourceName -g $ResourceGroup `
            --location $AiLocation --kind OpenAI --sku S0 `
            --custom-domain $AiResourceName --yes --output none
        if ($LASTEXITCODE -ne 0) { throw "Failed to create Foundry account '$AiResourceName'." }
        Write-Host "  Foundry account created." -ForegroundColor Green
    } else {
        Write-Host "  Foundry account '$AiResourceName' exists." -ForegroundColor Green
    }
    Set-ModelDeployment -Name 'gpt-5'                 -ModelName 'gpt-5'                 -Capacity $ChatCapacity
    Set-ModelDeployment -Name 'text-embedding-3-large' -ModelName 'text-embedding-3-large' -Capacity $EmbeddingCapacity
}
Write-Host ''

# ── 3. Server system-assigned managed identity (keyless caller) ──
Write-Host '[3] Server managed identity...' -ForegroundColor Yellow
$sqlMi = az sql server show -n $SqlServerName -g $ResourceGroup --query 'identity.principalId' -o tsv 2>$null
if (-not $sqlMi) {
    Write-Host "  Assigning system-assigned identity to $SqlServerName..." -ForegroundColor Gray
    az sql server update -n $SqlServerName -g $ResourceGroup --assign-identity --output none
    if ($LASTEXITCODE -ne 0) { throw "Failed to assign managed identity to $SqlServerName." }
    $sqlMi = az sql server show -n $SqlServerName -g $ResourceGroup --query 'identity.principalId' -o tsv 2>$null
}
if (-not $sqlMi) { throw "Could not resolve the server managed identity principalId." }
Write-Host "  Server MI principal: $sqlMi" -ForegroundColor Green
Write-Host ''

# ── 4. RBAC: server MI -> Cognitive Services OpenAI User on Foundry ──
Write-Host '[4] RBAC (server MI -> Cognitive Services OpenAI User on Foundry)...' -ForegroundColor Yellow
$aiId = az cognitiveservices account show -n $AiResourceName -g $ResourceGroup --query 'id' -o tsv
$haveRole = az role assignment list --assignee $sqlMi --scope $aiId --role 'Cognitive Services OpenAI User' --query '[0].id' -o tsv 2>$null
if ($haveRole) {
    Write-Host '  Already assigned.' -ForegroundColor Green
} else {
    az role assignment create --assignee $sqlMi --role 'Cognitive Services OpenAI User' --scope $aiId --output none
    if ($LASTEXITCODE -ne 0) { throw "Failed to grant the server MI access to Foundry." }
    Write-Host '  Assigned.' -ForegroundColor Green
}
Write-Host ''

# ── 5. APIM AI gateway + content safety (default; -NoGateway skips) ──
if ($Gateway) {
    Write-Host '[5] APIM AI gateway (setup-ai-gateway.ps1, ~30-45 min)...' -ForegroundColor Yellow
    $setupArgs = @{
        SubscriptionId = $SubscriptionId
        ResourceGroup  = $ResourceGroup
        ApimName       = $ApimName
        AiResourceName = $AiResourceName
        SqlServerName  = $SqlServerName
        PublisherEmail = $PublisherEmail
    }
    if ($Force) { $setupArgs['Force'] = $true }
    & (Join-Path $here 'setup-ai-gateway.ps1') @setupArgs
    if ($LASTEXITCODE -ne 0) { throw "setup-ai-gateway.ps1 failed." }

    if ($ContentSafety) {
        Write-Host ''
        Write-Host '[5b] Content safety (add-content-safety.ps1)...' -ForegroundColor Yellow
        $csArgs = @{
            SubscriptionId = $SubscriptionId
            ResourceGroup  = $ResourceGroup
            ApimName       = $ApimName
            CsResourceName = $CsResourceName
            SqlServerName  = $SqlServerName
        }
        & (Join-Path $here 'add-content-safety.ps1') @csArgs
        if ($LASTEXITCODE -ne 0) { throw "add-content-safety.ps1 failed." }
    }
    Write-Host ''
}

# ── Summary + next steps (DB objects run AFTER this) ──
Write-Host '=============================================' -ForegroundColor Green
Write-Host ' Azure AI layer ready.' -ForegroundColor Green
Write-Host ''
Write-Host ' NEXT — run the in-engine SQL yourself (it references what was just created).' -ForegroundColor Yellow
Write-Host '        First replace <your-foundry> in 06 and 08 with this Foundry resource name.' -ForegroundColor Gray
if ($Gateway) {
    Write-Host '        Then replace <your-apim> in 08 with the API Management service name.' -ForegroundColor Gray
} else {
    Write-Host '        No gateway: also change @UseGateway''s default in 08 from 1 to 0.' -ForegroundColor Yellow
}
Write-Host '   1. 06-ai-embeddings.sql          external model, vector table, the embeddings' -ForegroundColor Gray
Write-Host '   2. 07-vector-index.sql           the DiskANN vector index' -ForegroundColor Gray
Write-Host '   3. 08-ai-assistance.sql          the assistance proc + its append-only ledger' -ForegroundColor Gray
Write-Host '   4. 09-research-vector-search.sql the retrieval-only proc for the named replica' -ForegroundColor Gray
if (-not $Gateway) {
    Write-Host '   Later, if you add the gateway: re-run without -NoGateway, then re-run 08' -ForegroundColor Gray
}
Write-Host ''
Write-Host ' 06 embeds ~60K notes (~3-3.5 hr) — longer than an Entra token lives, so the' -ForegroundColor Gray
Write-Host ' connection WILL drop part-way. Expected. Reconnect and re-run its INSERT; it' -ForegroundColor Gray
Write-Host ' resumes. Check with verify-embeddings.sql and stop when MISSING=0.' -ForegroundColor Gray
Write-Host ''
Write-Host " Teardown (billable bits): az apim delete -n <your-apim-name> -g $ResourceGroup --yes --no-wait" -ForegroundColor Gray
Write-Host '=============================================' -ForegroundColor Green
