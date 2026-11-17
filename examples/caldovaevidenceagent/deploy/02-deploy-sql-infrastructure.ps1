[CmdletBinding()]
param(
    [string]$ClientIp
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\00-config.ps1"

Write-Host 'Caldova Evidence Agent: Stage 1 SQL infrastructure' -ForegroundColor Cyan
$account = Invoke-AzJson @('account', 'show', '--output', 'json')
if ($account.id -ne $ExpectedSubscriptionId -or $account.tenantId -ne $ExpectedTenantId) {
    throw 'Azure CLI is not using the subscription and tenant approved by pre-flight.'
}
$signedInUser = Invoke-AzJson @('ad', 'signed-in-user', 'show', '--output', 'json')
if (-not $ClientIp) { $ClientIp = Get-CurrentClientIp }

Write-Step "Resource group $ResourceGroup"
$resourceGroupExists = & az group exists --name $ResourceGroup --subscription $ExpectedSubscriptionId --output tsv
if ($resourceGroupExists -ne 'true') {
    Invoke-AzJson (@('group', 'create', '--subscription', $ExpectedSubscriptionId, '--name', $ResourceGroup,
        '--location', $PreferredLocation, '--tags') + $Tags + @('--output', 'json')) | Out-Null
}
Write-Ok 'Ready'

Write-Step "Foundry account $FoundryAccountName"
$foundry = Invoke-AzJson @('cognitiveservices', 'account', 'show', '--subscription', $ExpectedSubscriptionId,
    '--resource-group', $ResourceGroup, '--name', $FoundryAccountName, '--output', 'json') -AllowFailure
if (-not $foundry) {
    $foundry = Invoke-AzJson @('cognitiveservices', 'account', 'create', '--subscription', $ExpectedSubscriptionId,
        '--resource-group', $ResourceGroup, '--name', $FoundryAccountName, '--location', $FoundryLocation,
        '--kind', 'AIServices', '--sku', 'S0', '--custom-domain', $FoundryAccountName,
        '--assign-identity', '--yes', '--output', 'json')
}
Write-Ok "$($foundry.location), $($foundry.properties.endpoint)"

Write-Step "Embedding deployment $EmbeddingDeploymentName"
$embeddingDeployment = Invoke-AzJson @('cognitiveservices', 'account', 'deployment', 'show',
    '--subscription', $ExpectedSubscriptionId, '--resource-group', $ResourceGroup,
    '--name', $FoundryAccountName, '--deployment-name', $EmbeddingDeploymentName,
    '--output', 'json') -AllowFailure
if (-not $embeddingDeployment) {
    $catalog = Invoke-AzJson @('cognitiveservices', 'model', 'list', '--subscription', $ExpectedSubscriptionId,
        '--location', $FoundryLocation, '--output', 'json')
    $model = $catalog | Where-Object {
        $_.model.name -eq $EmbeddingModelName -and
        $_.model.skus.name -contains 'GlobalStandard' -and
        $_.model.isDefaultVersion
    } | Select-Object -First 1
    if (-not $model) { throw "No default GlobalStandard $EmbeddingModelName model found in $FoundryLocation." }
    $embeddingDeployment = Invoke-AzJson @('cognitiveservices', 'account', 'deployment', 'create',
        '--subscription', $ExpectedSubscriptionId, '--resource-group', $ResourceGroup,
        '--name', $FoundryAccountName, '--deployment-name', $EmbeddingDeploymentName,
        '--model-name', $EmbeddingModelName, '--model-version', $model.model.version,
        '--model-format', $model.model.format, '--sku-name', 'GlobalStandard',
        '--sku-capacity', $EmbeddingDeploymentCapacity, '--output', 'json')
}
Write-Ok "$($embeddingDeployment.properties.model.name) $($embeddingDeployment.properties.model.version)"

Write-Step "Entra-only SQL server $SqlServerName"
$server = Invoke-AzJson @('sql', 'server', 'show', '--subscription', $ExpectedSubscriptionId,
    '--resource-group', $ResourceGroup, '--name', $SqlServerName, '--output', 'json') -AllowFailure
if (-not $server) {
    $server = Invoke-AzJson @('sql', 'server', 'create', '--subscription', $ExpectedSubscriptionId,
        '--resource-group', $ResourceGroup, '--name', $SqlServerName, '--location', $PreferredLocation,
        '--enable-ad-only-auth', '--external-admin-principal-type', 'User',
        '--external-admin-name', $signedInUser.displayName, '--external-admin-sid', $signedInUser.id,
        '--assign-identity', '--minimal-tls-version', '1.2', '--enable-public-network', 'true',
        '--output', 'json')
}
if (-not $server.identity.principalId) { throw 'SQL logical server has no system-assigned managed identity.' }
Write-Ok "$($server.fullyQualifiedDomainName), identity $($server.identity.principalId)"

Write-Step 'SQL firewall rules'
Invoke-AzJson @('sql', 'server', 'firewall-rule', 'create', '--subscription', $ExpectedSubscriptionId,
    '--resource-group', $ResourceGroup, '--server', $SqlServerName, '--name', 'AllowAzureServices',
    '--start-ip-address', '0.0.0.0', '--end-ip-address', '0.0.0.0', '--output', 'json') | Out-Null
Invoke-AzJson @('sql', 'server', 'firewall-rule', 'create', '--subscription', $ExpectedSubscriptionId,
    '--resource-group', $ResourceGroup, '--server', $SqlServerName, '--name', $BootstrapFirewallRuleName,
    '--start-ip-address', $ClientIp, '--end-ip-address', $ClientIp, '--output', 'json') | Out-Null
Write-Ok "Azure services allowed; $ClientIp allowed by $BootstrapFirewallRuleName"

Write-Step "Hyperscale serverless database $DatabaseName"
$database = Invoke-AzJson @('sql', 'db', 'show', '--subscription', $ExpectedSubscriptionId,
    '--resource-group', $ResourceGroup, '--server', $SqlServerName, '--name', $DatabaseName,
    '--output', 'json') -AllowFailure
if (-not $database) {
    $database = Invoke-AzJson @('sql', 'db', 'create', '--subscription', $ExpectedSubscriptionId,
        '--resource-group', $ResourceGroup, '--server', $SqlServerName, '--name', $DatabaseName,
        '--edition', 'Hyperscale', '--compute-model', 'Serverless', '--family', 'Gen5',
        '--capacity', '2', '--min-capacity', $DatabaseMinCapacity.ToString([Globalization.CultureInfo]::InvariantCulture),
        '--backup-storage-redundancy', 'Local', '--zone-redundant', 'false', '--output', 'json')
}
if ($database.currentServiceObjectiveName -ne $DatabaseServiceObjective) {
    throw "Expected $DatabaseServiceObjective; found $($database.currentServiceObjectiveName)."
}
Write-Ok "$($database.currentServiceObjectiveName), $($database.status)"

Write-Step 'SQL managed identity access to the embedding model'
$existingRole = Invoke-AzJson @('role', 'assignment', 'list', '--subscription', $ExpectedSubscriptionId,
    '--assignee-object-id', $server.identity.principalId, '--scope', $foundry.id,
    '--role', 'Cognitive Services OpenAI User', '--output', 'json')
if (-not $existingRole) {
    Invoke-AzJson @('role', 'assignment', 'create', '--subscription', $ExpectedSubscriptionId,
        '--assignee-object-id', $server.identity.principalId, '--assignee-principal-type', 'ServicePrincipal',
        '--role', 'Cognitive Services OpenAI User', '--scope', $foundry.id, '--output', 'json') | Out-Null
}
Write-Ok 'Cognitive Services OpenAI User assigned'

Write-Host "`nStage 1 infrastructure ready." -ForegroundColor Green
Write-Host "SQL:     $($server.fullyQualifiedDomainName)/$DatabaseName"
Write-Host "Foundry: $($foundry.properties.endpoint)"
Write-Host 'Next: run 03-initialize-sql.ps1.'
