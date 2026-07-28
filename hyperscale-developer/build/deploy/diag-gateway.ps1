<#
.SYNOPSIS
    Diagnostic: bisect the APIM gateway policy to find which element causes the
    500 on the clinical-assistance (gpt-5) call. Applies one policy VARIANT, then
    runs clinical.GenerateClinicalAssistance @UseGateway=1 a few times and prints
    the return codes. Self-contained (does its own PUT + test) so it doesn't rely
    on reading flaky terminal output.

    Variants (cumulative):
      bare   = validate-azure-ad-token + set-backend + managed-identity ONLY
      tl     = bare + azure-openai-token-limit
      metric = bare + azure-openai-emit-token-metric
      all    = bare + token-limit + emit-metric   (== setup-ai-gateway.ps1 policy)
      cs     = all + llm-content-safety            (== add-content-safety.ps1 policy)

    RET=0 -> the gateway call succeeded (200). RET=500 -> that variant breaks it.

.EXAMPLE
    .\diag-gateway.ps1 -Variant bare
    .\diag-gateway.ps1 -Variant tl
#>
[CmdletBinding()]
param(
    [ValidateSet('bare','tl','metric','all','cs')][string]$Variant = 'bare',
    [int]    $EncounterId   = 249,
    [int]    $Times         = 2,
    [string] $SubscriptionId= '0efc44aa-c965-420f-aac4-fff305dbcc97',
    [string] $ResourceGroup = 'rg-collierhealth',
    [string] $ApimName      = 'collierhealth-ai-gateway',
    [string] $SqlServerName  = 'collierhealth-17',
    [string] $TokenAudience  = 'https://cognitiveservices.azure.com',
    [string] $Server         = 'collierhealth-17.database.windows.net',
    [string] $Database       = 'wardgeneral',
    [string] $SqlSim         = 'C:\bwsql\presentations\hyperscale-developer\utilities\sqlsim\sqlsim.exe'
)

$ErrorActionPreference = 'Stop'
$apiId      = 'azure-openai-api'
$apiVersion = '2024-06-01-preview'
$baseUrl    = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName"

$tenantId  = az account show --query tenantId -o tsv
$sqlPrin   = az sql server show -n $SqlServerName -g $ResourceGroup --query 'identity.principalId' -o tsv
$sqlAppId  = az ad sp show --id $sqlPrin --query appId -o tsv

$auth    = "<validate-azure-ad-token tenant-id=`"$tenantId`"><client-application-ids><application-id>$sqlAppId</application-id></client-application-ids><audiences><audience>$TokenAudience</audience></audiences></validate-azure-ad-token>"
$backend = "<set-backend-service backend-id=`"gpt5-backend`" /><authentication-managed-identity resource=`"https://cognitiveservices.azure.com`" />"
$tl      = "<azure-openai-token-limit tokens-per-minute=`"10000`" counter-key=`"wardgeneral-gpt5`" estimate-prompt-tokens=`"true`" tokens-consumed-header-name=`"x-tokens-consumed`" remaining-tokens-header-name=`"x-tokens-remaining`" />"
$metric  = "<azure-openai-emit-token-metric namespace=`"collierhealth-ai-gateway`"><dimension name=`"API`" value=`"@(context.Api.Name)`" /><dimension name=`"Deployment`" value=`"gpt-5`" /><dimension name=`"Operation`" value=`"ClinicalAssistance`" /></azure-openai-emit-token-metric>"
$cs      = "<llm-content-safety backend-id=`"contentsafety-backend`" shield-prompt=`"true`" enforce-on-completions=`"true`"><categories output-type=`"FourSeverityLevels`"><category name=`"Hate`" threshold=`"2`" /><category name=`"Sexual`" threshold=`"2`" /><category name=`"SelfHarm`" threshold=`"2`" /><category name=`"Violence`" threshold=`"2`" /></categories></llm-content-safety>"

$inner = switch ($Variant) {
    'bare'   { "$auth$backend" }
    'tl'     { "$auth$backend$tl" }
    'metric' { "$auth$backend$metric" }
    'all'    { "$auth$backend$tl$metric" }
    'cs'     { "$auth$backend$cs$tl$metric" }
}
$policy = "<policies><inbound><base />$inner</inbound><backend><forward-request timeout=`"120`" /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>"

# ── Apply the policy variant ──
$body = @{ properties = @{ format = 'xml'; value = $policy } } | ConvertTo-Json -Depth 10 -Compress
$bf = Join-Path $env:TEMP 'diag-pol.json'
[System.IO.File]::WriteAllText($bf, $body, [System.Text.UTF8Encoding]::new($false))
$putOut = Join-Path $env:TEMP 'diag-pol-out.json'
az rest --method PUT --url "$baseUrl/apis/$apiId/policies/policy`?api-version=$apiVersion" --body "@$bf" --output-file $putOut 2>$null
$putExit = $LASTEXITCODE
Start-Sleep -Seconds 3

# ── Read the policy back to CONFIRM what is actually live ──
$getOut = Join-Path $env:TEMP 'diag-getpol.json'
az rest --method GET --url "$baseUrl/apis/$apiId/policies/policy`?api-version=$apiVersion" --output-file $getOut 2>$null
$polText = (Get-Content -Raw $getOut -ErrorAction SilentlyContinue)

# ── Run the proc via the gateway $Times ──
$token = (az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv).Trim()
$runSql = "SET NOCOUNT ON; DECLARE @i INT=0; WHILE @i<$Times BEGIN EXEC clinical.GenerateClinicalAssistance @EncounterId=$EncounterId, @UseGateway=1; SET @i+=1; END;"
$rf = Join-Path $env:TEMP 'diag-run.sql'
[System.IO.File]::WriteAllText($rf, $runSql, [System.Text.UTF8Encoding]::new($false))
& $SqlSim -S $Server -d $Database -T $token -N s -i $rf 2>&1 | Out-Null

# ── Read ret codes + the full latest response payload ──
$readSql = "SET NOCOUNT ON; SELECT TOP $Times CONCAT('RET=',ResponseRetCode) AS a FROM clinical.AIAssistanceLog WHERE EncounterId=$EncounterId ORDER BY AssistanceId DESC; SELECT TOP 1 CAST(ResponsePayload AS NVARCHAR(900)) AS resp FROM clinical.AIAssistanceLog WHERE EncounterId=$EncounterId ORDER BY AssistanceId DESC;"
$readFile = Join-Path $env:TEMP 'diag-read.sql'
[System.IO.File]::WriteAllText($readFile, $readSql, [System.Text.UTF8Encoding]::new($false))
$readOut = & $SqlSim -S $Server -d $Database -T $token -N s -i $readFile 2>&1 | Out-String

# ── Write everything to a results file (reliable to read) ──
$results = Join-Path $PSScriptRoot 'diag-results.txt'
@(
    "=== variant=$Variant  encounter=$EncounterId  $(Get-Date -Format o) ===",
    "PUT az exit: $putExit",
    "POLICY LIVE: validate-aad=$([bool]($polText -match 'validate-azure-ad-token')) token-limit=$([bool]($polText -match 'token-limit')) emit-metric=$([bool]($polText -match 'emit-token-metric')) content-safety=$([bool]($polText -match 'content-safety'))",
    "--- sqlsim test output ---",
    $readOut
) | Set-Content -Path $results -Encoding UTF8
Write-Host "Wrote results to $results"

