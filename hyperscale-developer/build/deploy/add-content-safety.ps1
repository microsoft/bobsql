<#
    Ward General Hospital — Hyperscale developer demo
    add-content-safety.ps1 : layer Azure AI Content Safety onto the gateway,
                             covering BOTH the prompt AND the completion.

    collierhealth-ai is a kind=OpenAI account, which does NOT expose the
    Content Safety API. So this script stands up a dedicated Azure AI Content
    Safety resource (F0 = free tier), grants the gateway's managed identity
    "Cognitive Services User" on it, points a gateway backend at it, and
    rewrites the API policy to run every request through <llm-content-safety>.
    Because an APIM policy PUT is a FULL REPLACE, this rewrite RE-INCLUDES the
    validate-azure-ad-token (managed-identity) block from setup-ai-gateway.ps1 so
    it never drops the passwordless auth. Keep the two policies in sync.

    COMPLETE input + output protection with one inbound policy element:
      * shield-prompt="true"          -> jailbreak / prompt-injection detection
      * <categories>                  -> Hate / Sexual / SelfHarm / Violence on the PROMPT
      * enforce-on-completions="true" -> re-run those checks on the COMPLETION
    A blocked request or response returns HTTP 403 from the gateway (the model
    is never billed on a blocked prompt).

    Verified against:
      https://learn.microsoft.com/azure/api-management/llm-content-safety-policy

    Run AFTER setup-ai-gateway.ps1. Idempotent — safe to re-run.
#>
param(
    [string] $SubscriptionId = '0efc44aa-c965-420f-aac4-fff305dbcc97',
    [string] $ResourceGroup  = 'rg-collierhealth',
    [string] $Location       = 'centralus',
    [string] $ApimName       = 'collierhealth-ai-gateway',
    [string] $CsResourceName = 'collierhealth-contentsafety',   # dedicated kind=ContentSafety resource
    [string] $CsSku          = 'F0',                            # F0 = free; S0 = pay-per-transaction
    [int]    $Threshold      = 2,                               # FourSeverityLevels: 0,2,4,6 (2 = strict)
    [string] $SqlServerName  = 'collierhealth-17',              # its MI is the ONLY authorized caller
    [string] $TokenAudience  = 'https://cognitiveservices.azure.com'  # first-party audience (matches setup-ai-gateway.ps1)
)

$ErrorActionPreference = 'Stop'
$apiId      = 'azure-openai-api'
$apiVersion = '2024-06-01-preview'
$baseUrl    = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName"

function Invoke-ApimRest {
    param([string]$Method, [string]$Path, [hashtable]$Body = $null)
    $url = "$baseUrl/$Path`?api-version=$apiVersion"
    if ($Body) {
        $bodyJson = $Body | ConvertTo-Json -Depth 10 -Compress
        $bodyFile = Join-Path $env:TEMP 'apim-rest-body.json'
        [System.IO.File]::WriteAllText($bodyFile, $bodyJson, [System.Text.UTF8Encoding]::new($false))
        $outFile = Join-Path $env:TEMP 'apim-rest-out.json'
        az rest --method $Method --url $url --body "@$bodyFile" --output-file $outFile 2>$null
        Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue
    } else {
        az rest --method $Method --url $url --output none 2>$null
    }
}

Write-Host '=== Adding Content Safety (input + output) to Ward General AI Gateway ===' -ForegroundColor Cyan
Write-Host ''
az account set --subscription $SubscriptionId | Out-Null

# ── Step 1: dedicated Content Safety resource (collierhealth-ai is OpenAI-only) ──
Write-Host "[1/4] Content Safety resource ($CsResourceName, $CsSku)..." -ForegroundColor Yellow
$csExists = az cognitiveservices account show --name $CsResourceName --resource-group $ResourceGroup --query 'name' -o tsv 2>$null
if ($csExists) {
    Write-Host '  Already exists.' -ForegroundColor Green
} else {
    az cognitiveservices account create `
        --name $CsResourceName --resource-group $ResourceGroup --location $Location `
        --kind ContentSafety --sku $CsSku --custom-domain $CsResourceName --yes --output none
    if ($LASTEXITCODE -ne 0) { Write-Host '  ERROR creating Content Safety resource.' -ForegroundColor Red; exit 1 }
    Write-Host '  Created.' -ForegroundColor Green
}
$csResourceId = az cognitiveservices account show --name $CsResourceName --resource-group $ResourceGroup --query 'id' -o tsv
Write-Host ''

# ── Step 2: grant the gateway's managed identity Cognitive Services User on it ──
Write-Host '[2/4] Granting gateway MI "Cognitive Services User" on Content Safety...' -ForegroundColor Yellow
$principalId = az rest --method GET --url "$baseUrl`?api-version=$apiVersion" --query 'identity.principalId' -o tsv
$existingRole = az role assignment list --assignee $principalId --scope $csResourceId --role 'Cognitive Services User' --query '[0].id' -o tsv 2>$null
if ($existingRole) {
    Write-Host '  Already assigned.' -ForegroundColor Green
} else {
    az role assignment create --assignee $principalId --role 'Cognitive Services User' --scope $csResourceId --output none
    if ($LASTEXITCODE -ne 0) { Write-Host '  ERROR' -ForegroundColor Red; exit 1 }
    Write-Host '  Assigned.' -ForegroundColor Green
}
Write-Host ''

# ── Step 3: content-safety backend (URL must be .cognitiveservices.azure.com) ──
Write-Host '[3/4] Creating content-safety backend...' -ForegroundColor Yellow
$csUrl = "https://${CsResourceName}.cognitiveservices.azure.com"
Invoke-ApimRest -Method PUT -Path 'backends/contentsafety-backend' -Body @{
    properties = @{ url = $csUrl; protocol = 'http'; description = 'Azure AI Content Safety' }
}
if ($LASTEXITCODE -ne 0) { Write-Host '  ERROR' -ForegroundColor Red; exit 1 }
Write-Host "  Backend: $csUrl" -ForegroundColor Green
Write-Host ''

# ── Step 4: rewrite the API policy = the MI-auth policy PLUS content safety ──
# CRITICAL: an APIM policy PUT is a FULL REPLACE, so this MUST re-include the
# validate-azure-ad-token block from setup-ai-gateway.ps1 (keep them in sync) or it
# would drop the passwordless auth. We insert <llm-content-safety> into that policy.
Write-Host '[4/4] Updating policy (validate-azure-ad-token + content safety)...' -ForegroundColor Yellow
$tenantId = az account show --query tenantId -o tsv
$sqlPrincipalId = az sql server show -n $SqlServerName -g $ResourceGroup --query 'identity.principalId' -o tsv 2>$null
if (-not $sqlPrincipalId) { Write-Host "  ERROR: $SqlServerName has no system-assigned managed identity." -ForegroundColor Red; exit 1 }
$sqlAppId = az ad sp show --id $sqlPrincipalId --query appId -o tsv
$t = $Threshold
$policyXml = @"
<policies><inbound><base /><validate-azure-ad-token tenant-id="$tenantId"><client-application-ids><application-id>$sqlAppId</application-id></client-application-ids><audiences><audience>$TokenAudience</audience></audiences></validate-azure-ad-token><set-backend-service backend-id="gpt5-backend" /><authentication-managed-identity resource="https://cognitiveservices.azure.com" /><llm-content-safety backend-id="contentsafety-backend" shield-prompt="true" enforce-on-completions="true"><categories output-type="FourSeverityLevels"><category name="Hate" threshold="$t" /><category name="Sexual" threshold="$t" /><category name="SelfHarm" threshold="$t" /><category name="Violence" threshold="$t" /></categories></llm-content-safety><azure-openai-token-limit tokens-per-minute="10000" counter-key="wardgeneral-gpt5" estimate-prompt-tokens="true" tokens-consumed-header-name="x-tokens-consumed" remaining-tokens-header-name="x-tokens-remaining" /><azure-openai-emit-token-metric namespace="collierhealth-ai-gateway"><dimension name="API" value="@(context.Api.Name)" /><dimension name="Deployment" value="gpt-5" /><dimension name="Operation" value="ClinicalAssistance" /></azure-openai-emit-token-metric></inbound><backend><forward-request timeout="120" /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>
"@
Invoke-ApimRest -Method PUT -Path "apis/$apiId/policies/policy" -Body @{
    properties = @{ format = 'xml'; value = $policyXml }
}
if ($LASTEXITCODE -ne 0) { Write-Host '  WARNING: check the portal.' -ForegroundColor Yellow }
else { Write-Host "  Policy updated (validate-azure-ad-token + content safety, threshold=$t)." -ForegroundColor Green }

Write-Host ''
Write-Host '=== Content Safety Active (input + output) ===' -ForegroundColor Green
Write-Host '  Prompt + completion: Hate, Sexual, SelfHarm, Violence' -ForegroundColor Gray
Write-Host '  shield-prompt: jailbreak / prompt-injection detection' -ForegroundColor Gray
Write-Host '  Blocked prompt OR completion -> HTTP 403 from the gateway' -ForegroundColor Gray
Write-Host "  Teardown CS resource: az cognitiveservices account delete -n $CsResourceName -g $ResourceGroup" -ForegroundColor Gray
