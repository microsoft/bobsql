<#
.SYNOPSIS
    Deploy the ENTIRE Azure AI layer for the Ward General Hyperscale demo in one
    command: the Microsoft Foundry (Azure OpenAI) resource + model deployments,
    the passwordless managed-identity wiring, RBAC, and (optionally) the APIM AI
    gateway + content safety.

.DESCRIPTION
    This is the Azure control-plane orchestrator for the AI layer. It sits BETWEEN
    the database provision and the in-engine SQL objects:

        1. provision-hyperscale.ps1   (deploy-wardgeneral-db)  — server + wardgeneral DB
        2. azureaideploy.ps1          (THIS)                    — Foundry + APIM + MIs + RBAC
        3. DB objects: sql/06 + sql/07 (+ sql/09 if -Gateway) then generate-embeddings.ps1

    What it does (all idempotent — "create if absent"; safe to re-run):
      - Foundry (Azure OpenAI) account `collierhealth-ai` (kind=OpenAI, custom
        subdomain — required for Entra token auth). Created only if missing.
      - Model deployments: `gpt-5` and `text-embedding-3-large`, both
        GlobalStandard at capacity 100 (pinned so a fresh deploy never needs a
        manual TPM bump).
      - The wardgeneral server's SYSTEM-ASSIGNED MANAGED IDENTITY (assigned if
        absent) — the keyless caller for both the direct Foundry path and the
        gateway path.
      - RBAC: server MI -> "Cognitive Services OpenAI User" on the Foundry account.
      - (-Gateway) delegates to setup-ai-gateway.ps1 — APIM StandardV2 + its own
        MI + a validate-azure-ad-token policy (accepts ONLY the server MI on the
        first-party Cognitive Services audience — no app registration).
        (-ContentSafety) adds input/output moderation.

    What it does NOT do (deliberate — different owners / different lifecycles):
      - It does NOT create the resource group, the SQL server, or the database
        (that is provision-hyperscale.ps1 / deploy-wardgeneral-db; the DB is
        SHARED with the book — never recreated here).
      - It does NOT run the in-engine SQL (06/07/09) or build embeddings. Those
        reference the resources created here and run AFTER (see the printed next
        steps). The DB objects honor `GO`, so run them with the MSSQL extension /
        ADS; bulk-embed with generate-embeddings.ps1.

    Cost/time: model deployments + RBAC are quick. -Gateway adds a real, always-on
    APIM StandardV2 (~30-45 min to provision, billable).

.PARAMETER Gateway
    Also provision the APIM AI gateway (setup-ai-gateway.ps1).

.PARAMETER ContentSafety
    Also add content safety to the gateway (implies -Gateway).

.PARAMETER SkipModels
    Skip Foundry account + model deployment (assume they already exist); still do
    the MI + RBAC (+ optional gateway).

.PARAMETER Force
    Passed through to setup-ai-gateway.ps1 (recreate APIM from scratch).

.EXAMPLE
    .\azureaideploy.ps1                          # Foundry + models + MI + RBAC (no gateway)
    .\azureaideploy.ps1 -Gateway                 # + APIM gateway
    .\azureaideploy.ps1 -Gateway -ContentSafety  # + gateway + input/output content safety
#>
[CmdletBinding()]
param(
    [string] $SubscriptionId    = ($env:SUBSCRIPTION_ID ?? '0efc44aa-c965-420f-aac4-fff305dbcc97'),
    [string] $ResourceGroup     = ($env:RG ?? 'rg-collierhealth'),
    [string] $AiResourceName    = ($env:AI_RESOURCE ?? 'collierhealth-ai'),
    [string] $AiLocation        = ($env:AI_LOCATION ?? 'eastus2'),
    [string] $SqlServerName     = ($env:SRV ?? 'collierhealth-17'),
    [int]    $ChatCapacity      = 100,
    [int]    $EmbeddingCapacity = 100,
    [switch] $Gateway,
    [switch] $ContentSafety,
    [switch] $SkipModels,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($ContentSafety) { $Gateway = $true }   # content safety attaches to the gateway policy

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
Write-Host '[1] Setting subscription...' -ForegroundColor Yellow
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { Write-Host "  ERROR: run 'az login' first." -ForegroundColor Red; exit 1 }
Write-Host '  OK' -ForegroundColor Green
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

# ── 5. (optional) APIM AI gateway + content safety ──
if ($Gateway) {
    Write-Host '[5] APIM AI gateway (setup-ai-gateway.ps1, ~30-45 min)...' -ForegroundColor Yellow
    $setupArgs = @{ SqlServerName = $SqlServerName }
    if ($Force) { $setupArgs['Force'] = $true }
    & (Join-Path $here 'setup-ai-gateway.ps1') @setupArgs
    if ($LASTEXITCODE -ne 0) { throw "setup-ai-gateway.ps1 failed." }

    if ($ContentSafety) {
        Write-Host ''
        Write-Host '[5b] Content safety (add-content-safety.ps1)...' -ForegroundColor Yellow
        & (Join-Path $here 'add-content-safety.ps1')
        if ($LASTEXITCODE -ne 0) { throw "add-content-safety.ps1 failed." }
    }
    Write-Host ''
}

# ── Summary + next steps (DB objects run AFTER this) ──
Write-Host '=============================================' -ForegroundColor Green
Write-Host ' Azure AI layer ready.' -ForegroundColor Green
Write-Host ''
Write-Host ' NEXT — build the in-engine DB objects (they reference what was just created):' -ForegroundColor Yellow
Write-Host '   1. deploy/deploy-sql.ps1 -Scripts 06-ai-embeddings' -ForegroundColor Gray
Write-Host '   2. deploy/generate-embeddings.ps1   (bulk-embed ~60K notes, resumable)' -ForegroundColor Gray
Write-Host '   3. deploy/deploy-sql.ps1 -Scripts 07-ai-assistance' -ForegroundColor Gray
if ($Gateway) {
    Write-Host '   4. sql/09-ai-gateway.sql   (first-party audience baked in — no edits)' -ForegroundColor Gray
    Write-Host '        run-ai-gateway-e2e.ps1 -SkipSetup   deploys 09 + verifies the gateway call' -ForegroundColor Gray
}
Write-Host ''
Write-Host " Teardown (billable bits): az apim delete -n collierhealth-ai-gateway -g $ResourceGroup --yes --no-wait" -ForegroundColor Gray
Write-Host '=============================================' -ForegroundColor Green
