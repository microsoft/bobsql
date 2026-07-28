<#
.SYNOPSIS
    Deploy an Azure API Management AI Gateway in front of the Collier Health
    Foundry (Azure OpenAI) resource, for the Ward General Hyperscale demo.

.DESCRIPTION
    Puts an APIM StandardV2 instance between the wardgeneral database and the
    gpt-5 chat deployment on collierhealth-ai. The clinical assistance
    proc (clinical.GenerateClinicalAssistance) doesn't change its logic —
    09-ai-gateway.sql just swaps the URL + credential it calls, so every AI
    interaction is now governed: token rate-limiting, token metrics, managed-
    identity auth (no key in transit), and (via add-content-safety.ps1)
    content-safety filtering.

    This mirrors the zavalending demo3 gateway exactly (setup-ai-gateway.ps1),
    adapted to the Collier Health resources. Uses the ARM REST API throughout
    (the `az apim backend/subscription/policy` subcommands aren't in every CLI
    version). Idempotent — safe to re-run; each step checks for existence.

    Components created:
      - APIM StandardV2 instance (collierhealth-ai-gateway) + system MI
      - MI granted "Cognitive Services OpenAI User" on collierhealth-ai
      - gpt-5 backend -> the resource's own endpoint (<name>.openai.azure.com/openai)
      - azure-openai-api (subscription NOT required) with a chat-completions operation
      - Policies: validate-azure-ad-token (accept ONLY the wardgeneral server's
        managed identity, on the FIRST-PARTY Cognitive Services audience — no app
        registration), set-backend-service, managed-identity auth to gpt-5,
        10K TPM limit, token metrics

    Cost/time note: APIM StandardV2 is a real, always-on billable resource and
    provisioning takes ~30-45 minutes. Tear down after the talk with:
      az apim delete -n collierhealth-ai-gateway -g rg-collierhealth --yes --no-wait

    Fully passwordless: the database calls APIM with the SAME first-party managed-
    identity token the direct Foundry path uses (audience
    https://cognitiveservices.azure.com) — no subscription key, no custom app
    registration, nothing to paste into 09-ai-gateway.sql.

.PARAMETER Force
    Delete and recreate the APIM instance from scratch.

.EXAMPLE
    .\setup-ai-gateway.ps1
    .\setup-ai-gateway.ps1 -Force
#>
param(
    [switch] $Force,
    [string] $SubscriptionId = '0efc44aa-c965-420f-aac4-fff305dbcc97',
    [string] $ResourceGroup  = 'rg-collierhealth',
    [string] $Location       = 'centralus',
    [string] $ApimName       = 'collierhealth-ai-gateway',
    [string] $AiResourceName = 'collierhealth-ai',
    [string] $PublisherEmail = 'bobward@microsoft.com',
    [string] $PublisherName  = 'Collier Health',
    [string] $SqlServerName   = 'collierhealth-17',
    # The DB->APIM hop authenticates with the SAME first-party token the direct Foundry
    # path uses (06/07) — no custom app registration, no Service Tree ID.
    [string] $TokenAudience   = 'https://cognitiveservices.azure.com'
)

$ErrorActionPreference = 'Stop'

# ── Configuration ──
$backendId  = 'gpt5-backend'
$apiId      = 'azure-openai-api'
$apiVersion = '2024-06-01-preview'
$baseUrl    = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName"

function Invoke-ApimRest {
    param([string]$Method, [string]$Path, [hashtable]$Body = $null, [switch]$OutputFile)
    $url = "$baseUrl/$Path`?api-version=$apiVersion"
    if ($Body) {
        $bodyJson = $Body | ConvertTo-Json -Depth 10 -Compress
        $bodyFile = Join-Path $env:TEMP 'apim-rest-body.json'
        # Write without BOM — az rest chokes on BOM in responses that carry policy XML.
        [System.IO.File]::WriteAllText($bodyFile, $bodyJson, [System.Text.UTF8Encoding]::new($false))
        if ($OutputFile) {
            $outFile = Join-Path $env:TEMP 'apim-rest-out.json'
            az rest --method $Method --url $url --body "@$bodyFile" --output-file $outFile 2>$null
            $result = [System.IO.File]::ReadAllText($outFile, [System.Text.UTF8Encoding]::new($false))
        } else {
            $result = az rest --method $Method --url $url --body "@$bodyFile" 2>&1
        }
        Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue
    } else {
        if ($OutputFile) {
            $outFile = Join-Path $env:TEMP 'apim-rest-out.json'
            az rest --method $Method --url $url --output-file $outFile 2>$null
            $result = [System.IO.File]::ReadAllText($outFile, [System.Text.UTF8Encoding]::new($false))
        } else {
            $result = az rest --method $Method --url $url 2>&1
        }
    }
    return $result
}

$totalSteps = 8

Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ' Ward General AI Gateway Setup'               -ForegroundColor Cyan
Write-Host " APIM:     $ApimName (StandardV2)"           -ForegroundColor Cyan
Write-Host " Backend:  $AiResourceName (gpt-5)"          -ForegroundColor Cyan
Write-Host " Region:   $Location"                        -ForegroundColor Cyan
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ''

# ── Step 1: Subscription ──
Write-Host "[1/$totalSteps] Setting subscription..." -ForegroundColor Yellow
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { Write-Host "  ERROR: Run 'az login' first." -ForegroundColor Red; exit 1 }
Write-Host '  OK' -ForegroundColor Green
Write-Host ''

# ── Preflight: EVERYTHING that doesn't need APIM, up front ──
# Fail fast BEFORE the ~45-min APIM provision. All of this is independent of the
# gateway instance (SQL MI + its appId, gpt-5 deployment, tenant), so any missing
# prerequisite costs seconds, not 45 minutes of provisioning followed by a late
# failure. Only Step 5 (RBAC on the APIM principal) and Step 7 (policy on the APIM
# instance) genuinely require APIM to exist first.
Write-Host '[*] Preflight (no APIM required yet)...' -ForegroundColor Yellow

# 1. SQL server system-assigned managed identity (the ONLY authorized caller).
$sqlPrincipalId = az sql server show -n $SqlServerName -g $ResourceGroup --query 'identity.principalId' -o tsv 2>$null
if (-not $sqlPrincipalId) {
    Write-Host "  ERROR: SQL server '$SqlServerName' has no system-assigned managed identity." -ForegroundColor Red
    Write-Host "         Enable it first:  az sql server update -n $SqlServerName -g $ResourceGroup --assign-identity" -ForegroundColor Red
    exit 1
}
$sqlAppId = az ad sp show --id $sqlPrincipalId --query appId -o tsv 2>$null
if (-not $sqlAppId) { Write-Host "  ERROR: could not resolve the SQL MI appId from principal $sqlPrincipalId." -ForegroundColor Red; exit 1 }
Write-Host "  SQL MI: principal $sqlPrincipalId / appId $sqlAppId" -ForegroundColor Green

# 2. gpt-5 deployment (the gateway backend).
$pfGpt = az cognitiveservices account deployment list -n $AiResourceName -g $ResourceGroup --query "[?name=='gpt-5'].name" -o tsv 2>$null
if (-not $pfGpt) {
    Write-Host "  ERROR: '$AiResourceName' has no 'gpt-5' deployment (the gateway backend)." -ForegroundColor Red
    exit 1
}
Write-Host '  gpt-5 deployment present.' -ForegroundColor Green

# 3. Tenant + the token audience the DB requests. We reuse the FIRST-PARTY Cognitive
#    Services audience (the SAME token the direct Foundry path uses in 06/07) instead of a
#    custom app registration — nothing to register, no Service Tree ID. The gateway's real
#    authorization gate is client-application-ids below (the SQL MI ONLY), NOT the audience,
#    so a shared first-party audience does not widen who APIM accepts.
$tenantId = az account show --query tenantId -o tsv
Write-Host "  Token audience (first-party, no app registration): $TokenAudience" -ForegroundColor Green
Write-Host ''

# ── Step 2: Register provider ──
Write-Host "[2/$totalSteps] Checking Microsoft.ApiManagement provider..." -ForegroundColor Yellow
$provState = az provider show --namespace Microsoft.ApiManagement --query 'registrationState' -o tsv 2>$null
if ($provState -ne 'Registered') {
    Write-Host '  Registering provider...' -ForegroundColor Gray
    az provider register --namespace Microsoft.ApiManagement --output none
    do {
        Start-Sleep -Seconds 10
        $provState = az provider show --namespace Microsoft.ApiManagement --query 'registrationState' -o tsv
        Write-Host "  State: $provState"
    } while ($provState -ne 'Registered')
}
Write-Host '  Registered' -ForegroundColor Green
Write-Host ''

# ── Step 3: Create APIM instance ──
Write-Host "[3/$totalSteps] Creating APIM instance (StandardV2, ~30-45 min)..." -ForegroundColor Yellow
if ($Force) {
    Write-Host '  Force cleanup...' -ForegroundColor Gray
    az rest --method DELETE --url "$baseUrl`?api-version=$apiVersion" --output none 2>$null
    Start-Sleep -Seconds 10
}
$existing = az rest --method GET --url "$baseUrl`?api-version=$apiVersion" --query 'properties.provisioningState' -o tsv 2>$null
if ($existing -eq 'Succeeded') {
    Write-Host '  Already exists and ready.' -ForegroundColor Green
} else {
    # StandardV2 isn't supported by `az apim create`; PUT the ARM resource directly.
    $createBody = @{
        location   = $Location
        sku        = @{ name = 'StandardV2'; capacity = 1 }
        identity   = @{ type = 'SystemAssigned' }
        properties = @{ publisherEmail = $PublisherEmail; publisherName = $PublisherName }
    }
    $bodyJson = $createBody | ConvertTo-Json -Depth 5 -Compress
    $bodyFile = Join-Path $env:TEMP 'apim-create.json'
    [System.IO.File]::WriteAllText($bodyFile, $bodyJson, [System.Text.UTF8Encoding]::new($false))
    az rest --method PUT --url "$baseUrl`?api-version=$apiVersion" --body "@$bodyFile" --output none
    Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -ne 0) { Write-Host '  ERROR: APIM creation failed.' -ForegroundColor Red; exit 1 }

    Write-Host '  Waiting for provisioning...' -ForegroundColor Gray
    do {
        Start-Sleep -Seconds 15
        $state = az rest --method GET --url "$baseUrl`?api-version=$apiVersion" --query 'properties.provisioningState' -o tsv 2>$null
        Write-Host "  State: $state"
    } while ($state -ne 'Succeeded' -and $state -ne 'Failed')
    if ($state -ne 'Succeeded') { Write-Host "  ERROR: Provisioning $state" -ForegroundColor Red; exit 1 }
    Write-Host '  Created.' -ForegroundColor Green
}
Write-Host ''

# ── Step 4: Gateway URL + principal ──
Write-Host "[4/$totalSteps] Getting gateway details..." -ForegroundColor Yellow
$apimInfo = az rest --method GET --url "$baseUrl`?api-version=$apiVersion" --query '{gatewayUrl:properties.gatewayUrl, principalId:identity.principalId}' -o json | ConvertFrom-Json
$gatewayUrl  = $apimInfo.gatewayUrl
$principalId = $apimInfo.principalId
Write-Host "  Gateway:    $gatewayUrl"  -ForegroundColor Green
Write-Host "  Principal:  $principalId" -ForegroundColor Green
Write-Host ''

# ── Step 5: RBAC ──
Write-Host "[5/$totalSteps] Granting 'Cognitive Services OpenAI User' role..." -ForegroundColor Yellow
$aiResourceId = az cognitiveservices account show --name $AiResourceName --resource-group $ResourceGroup --query 'id' -o tsv
$existingRole = az role assignment list --assignee $principalId --scope $aiResourceId --role 'Cognitive Services OpenAI User' --query '[0].id' -o tsv 2>$null
if ($existingRole) {
    Write-Host '  Already assigned.' -ForegroundColor Green
} else {
    az role assignment create --assignee $principalId --role 'Cognitive Services OpenAI User' --scope $aiResourceId --output none
    if ($LASTEXITCODE -ne 0) { Write-Host '  ERROR' -ForegroundColor Red; exit 1 }
    Write-Host '  Assigned.' -ForegroundColor Green
}
Write-Host ''

# ── Step 6: Backend ──
Write-Host "[6/$totalSteps] Creating gpt-5 backend..." -ForegroundColor Yellow
# Use the resource's ACTUAL endpoint. For kind=OpenAI that is <name>.openai.azure.com;
# the <name>.cognitiveservices.azure.com alias does NOT resolve for this resource, so
# hardcoding it makes APIM fail to reach the backend and return 500 on every call.
$aiEndpoint = (az cognitiveservices account show -n $AiResourceName -g $ResourceGroup --query 'properties.endpoint' -o tsv).TrimEnd('/')
$backendUrl = "$aiEndpoint/openai"
$result = Invoke-ApimRest -Method PUT -Path "backends/$backendId" -Body @{
    properties = @{ url = $backendUrl; protocol = 'http'; description = 'Azure OpenAI - gpt-5' }
}
if ($LASTEXITCODE -ne 0) { Write-Host "  ERROR: $result" -ForegroundColor Red; exit 1 }
Write-Host "  Backend: $backendUrl" -ForegroundColor Green
Write-Host ''

# ── Step 7: API + operation + policies ──
Write-Host "[7/$totalSteps] Creating API, operation, and policies..." -ForegroundColor Yellow
$result = Invoke-ApimRest -Method PUT -Path "apis/$apiId" -Body @{
    properties = @{
        displayName          = 'Azure OpenAI - Collier Health'
        path                 = 'openai'
        protocols            = @('https')
        serviceUrl           = $backendUrl
        subscriptionRequired = $false
    }
}
if ($LASTEXITCODE -ne 0) { Write-Host '  ERROR creating API' -ForegroundColor Red; exit 1 }
Write-Host '  API created.' -ForegroundColor Green

$result = Invoke-ApimRest -Method PUT -Path "apis/$apiId/operations/chat-completions" -Body @{
    properties = @{
        displayName        = 'Chat Completions'
        method             = 'POST'
        urlTemplate        = '/deployments/{deployment-id}/chat/completions'
        templateParameters = @(@{ name = 'deployment-id'; required = $true; type = 'string'; description = 'Model deployment name' })
    }
}
Write-Host '  Operation created.' -ForegroundColor Green

# Policy: accept ONLY the wardgeneral server's managed-identity token (validate-azure-ad-token),
# route to gpt5-backend, auth to Azure OpenAI with APIM's managed identity, cap at 10K TPM, emit token metrics.
$policyXml = @"
<policies><inbound><base /><validate-azure-ad-token tenant-id="$tenantId"><client-application-ids><application-id>$sqlAppId</application-id></client-application-ids><audiences><audience>$TokenAudience</audience></audiences></validate-azure-ad-token><set-backend-service backend-id="gpt5-backend" /><authentication-managed-identity resource="https://cognitiveservices.azure.com" /><azure-openai-token-limit tokens-per-minute="10000" counter-key="wardgeneral-gpt5" estimate-prompt-tokens="true" tokens-consumed-header-name="x-tokens-consumed" remaining-tokens-header-name="x-tokens-remaining" /><azure-openai-emit-token-metric namespace="collierhealth-ai-gateway"><dimension name="API" value="@(context.Api.Name)" /><dimension name="Deployment" value="gpt-5" /><dimension name="Operation" value="ClinicalAssistance" /></azure-openai-emit-token-metric></inbound><backend><forward-request timeout="120" /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>
"@
$result = Invoke-ApimRest -Method PUT -Path "apis/$apiId/policies/policy" -Body @{
    properties = @{ format = 'xml'; value = $policyXml }
} -OutputFile
Write-Host '  Policies applied: validate-azure-ad-token (wardgeneral MI only), managed identity to gpt-5, 10K TPM limit, token metrics' -ForegroundColor Green
Write-Host ''

# ── Step 8: Passwordless — no key to retrieve ──
Write-Host "[8/$totalSteps] Passwordless gateway ready — no key, no app registration." -ForegroundColor Yellow
Write-Host '  09-ai-gateway.sql already uses the first-party audience — nothing to paste:' -ForegroundColor Green
Write-Host "    $TokenAudience" -ForegroundColor White

Write-Host ''
Write-Host '=============================================' -ForegroundColor Green
Write-Host ' AI Gateway Ready'                            -ForegroundColor Green
Write-Host " $gatewayUrl"                                 -ForegroundColor White
Write-Host ''
Write-Host ' Policies: validate-azure-ad-token (caller = wardgeneral MI), managed-identity auth to gpt-5, 10K TPM, token metrics' -ForegroundColor Gray
Write-Host ''
Write-Host ' Next:  (optional) .\add-content-safety.ps1' -ForegroundColor Yellow
Write-Host '        then run sql\09-ai-gateway.sql (no edits needed — first-party audience baked in)' -ForegroundColor Yellow
Write-Host " Teardown: az apim delete -n $ApimName -g $ResourceGroup --yes --no-wait" -ForegroundColor Gray
Write-Host '=============================================' -ForegroundColor Green
