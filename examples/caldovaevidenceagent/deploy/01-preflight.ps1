[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\00-config.ps1"

Write-Host 'Caldova Evidence Agent: read-only pre-flight' -ForegroundColor Cyan

Write-Step 'Required tools'
foreach ($commandName in @('az', 'pwsh')) {
    $command = Get-Command $commandName -ErrorAction SilentlyContinue
    if (-not $command) { throw "Required command '$commandName' was not found." }
    Write-Ok "$commandName = $($command.Source)"
}
$python = Get-PythonCommand
Write-Ok "python = $python"

Write-Step 'Azure CLI context'
$account = Invoke-AzJson @('account', 'show', '--output', 'json')
if ($account.id -ne $ExpectedSubscriptionId) {
    throw "Expected subscription $ExpectedSubscriptionId, but Azure CLI selected $($account.id) ($($account.name))."
}
if ($account.tenantId -ne $ExpectedTenantId) {
    throw "Expected tenant $ExpectedTenantId, but Azure CLI selected $($account.tenantId)."
}
Write-Ok "$($account.name) ($($account.id))"
Write-Ok "Tenant $($account.tenantId)"

Write-Step 'Azure resource providers'
$requiredProviders = @(
    'Microsoft.App',
    'Microsoft.CognitiveServices',
    'Microsoft.ContainerRegistry',
    'Microsoft.ManagedIdentity',
    'Microsoft.Sql'
)
$providers = Invoke-AzJson @('provider', 'list', '--query', '[].{namespace:namespace,state:registrationState}', '--output', 'json')
foreach ($namespace in $requiredProviders) {
    $provider = $providers | Where-Object namespace -eq $namespace
    if (-not $provider -or $provider.state -ne 'Registered') {
        throw "Provider $namespace is not registered. Current state: $($provider.state)"
    }
    Write-Ok "$namespace registered"
}

Write-Step 'Curated corpus integrity'
$manifestPath = Join-Path $CorpusPath 'manifest.json'
if (-not (Test-Path $manifestPath)) {
    throw "Corpus manifest not found at $manifestPath. Restore the text-only curated corpus before running pre-flight."
}
$manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json
foreach ($sectionName in @('documents', 'chunks')) {
    $section = $manifest.$sectionName
    $path = Join-Path $CorpusPath $section.path
    if (-not (Test-Path $path)) { throw "Corpus file not found: $path" }
    $actualHash = (Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $section.sha256.ToLowerInvariant()) {
        throw "$($section.path) failed SHA-256 validation."
    }
    Write-Ok "$($section.path): $($section.rows) rows, SHA-256 verified"
}
if ($manifest.documents.rows -ne 30 -or $manifest.chunks.rows -ne 2834) {
    throw "Expected 30 documents and 2,834 chunks; manifest reports $($manifest.documents.rows) and $($manifest.chunks.rows)."
}
if (@($manifest.coverage).Count -ne 14) {
    throw "Expected 14 retrieval evaluation questions; found $(@($manifest.coverage).Count)."
}
Write-Ok '30 articles, 2,834 passages, and 14 evaluation questions'

Write-Step "Azure SQL offering in $PreferredLocation"
$editions = Invoke-AzJson @('sql', 'db', 'list-editions', '--subscription', $ExpectedSubscriptionId,
    '--location', $PreferredLocation, '--available', '--output', 'json')
$sqlObjective = foreach ($edition in $editions) {
    foreach ($objective in $edition.supportedServiceLevelObjectives) {
        if ($objective.name -eq $DatabaseServiceObjective) {
            [pscustomobject]@{ Edition = $edition.name; Objective = $objective.name; Status = $edition.status }
        }
    }
}
if (-not $sqlObjective -or $sqlObjective.Status -ne 'Available') {
    throw "$DatabaseServiceObjective is not available in $PreferredLocation for this subscription."
}
Write-Ok "$($sqlObjective.Objective) is available"

Write-Step 'Foundry model catalog and quota'
$usage = Invoke-AzJson @('cognitiveservices', 'usage', 'list', '--subscription', $ExpectedSubscriptionId,
    '--location', $PreferredLocation, '--output', 'json')
$selectedLocation = $null
$modelEvidence = @()
foreach ($location in $CandidateLocations) {
    $catalog = Invoke-AzJson @('cognitiveservices', 'model', 'list', '--subscription', $ExpectedSubscriptionId,
        '--location', $location, '--output', 'json') -AllowFailure
    if (-not $catalog) {
        $modelEvidence += [pscustomobject]@{ Location = $location; Embedding = $false; Chat = $false }
        continue
    }

    $embedding = $catalog | Where-Object { $_.model.name -eq $EmbeddingModelName }
    $chat = $catalog | Where-Object { $_.model.name -eq $ChatModelName }
    $modelEvidence += [pscustomobject]@{
        Location = $location
        Embedding = [bool]$embedding
        Chat = [bool]$chat
    }
    if (-not $selectedLocation -and $embedding -and $chat) { $selectedLocation = $location }
}

$modelEvidence | Format-Table -AutoSize | Out-Host
foreach ($modelName in @($EmbeddingModelName, $ChatModelName)) {
    $quota = $usage | Where-Object { $_.name.value -eq "OpenAI.GlobalStandard.$modelName" } | Select-Object -First 1
    if (-not $quota) { throw "No GlobalStandard quota record found for $modelName." }
    $available = [decimal]$quota.limit - [decimal]$quota.currentValue
    if ($available -le 0) { throw "No available GlobalStandard quota remains for $modelName." }
    Write-Ok "$modelName quota available: $available (thousands of TPM)"
}
if (-not $selectedLocation) {
    throw "None of the candidate regions list both $EmbeddingModelName and $ChatModelName. Do not deploy until a common region is measured."
}
Write-Ok "First common model region: $selectedLocation"
if ($selectedLocation -ne $FoundryLocation) {
    throw "Configured Foundry region is $FoundryLocation, but the first measured common region is $selectedLocation. Review 00-config.ps1."
}
if ($FoundryLocation -ne $PreferredLocation) {
    Write-Warn "SQL will use $PreferredLocation; Foundry models will use $FoundryLocation."
}

Write-Step 'Bootstrap firewall address'
$clientIp = Get-CurrentClientIp
if ($clientIp -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw "Unexpected public IP response: $clientIp" }
Write-Ok "$BootstrapFirewallRuleName = $clientIp"

Write-Host "`nPre-flight passed. No Azure resources were created or modified." -ForegroundColor Green
Write-Host "Preferred SQL region: $PreferredLocation"
Write-Host "Foundry model region: $FoundryLocation"