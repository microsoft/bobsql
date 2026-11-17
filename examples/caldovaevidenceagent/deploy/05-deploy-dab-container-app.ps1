[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\00-config.ps1"

Write-Host 'Caldova Evidence Agent: Stage 2 SQL MCP Server' -ForegroundColor Cyan
$account = Invoke-AzJson @('account', 'show', '--output', 'json')
if ($account.id -ne $ExpectedSubscriptionId -or $account.tenantId -ne $ExpectedTenantId) {
    throw 'Azure CLI is not using the approved subscription and tenant.'
}

$dabRoot = Join-Path $PSScriptRoot '..\dab'
$configPath = Join-Path $dabRoot 'dab-config.json'
$deploymentImageTag = "$DabImageTag-$(Get-Date -Format 'yyyyMMddHHmmss')"

Write-Step 'DAB configuration'
if (-not (Test-Path $configPath)) { throw "DAB configuration not found at $configPath." }
$config = Get-Content -Raw $configPath | ConvertFrom-Json
if (@($config.entities.PSObject.Properties.Name).Count -ne 3 -or -not $config.runtime.mcp.enabled) {
    throw 'DAB configuration must enable MCP and expose exactly three entities.'
}
Write-Ok 'Validated DAB configuration present'

Write-Step "Container registry $ContainerRegistryName"
$registry = Invoke-AzJson @('acr', 'show', '--subscription', $ExpectedSubscriptionId,
    '--resource-group', $ResourceGroup, '--name', $ContainerRegistryName, '--output', 'json') -AllowFailure
if (-not $registry) {
    $registry = Invoke-AzJson @('acr', 'create', '--subscription', $ExpectedSubscriptionId,
        '--resource-group', $ResourceGroup, '--name', $ContainerRegistryName,
        '--location', $PreferredLocation, '--sku', 'Basic', '--admin-enabled', 'false', '--output', 'json')
}
Write-Ok $registry.loginServer

Write-Step 'Cloud build DAB image'
& az acr build --subscription $ExpectedSubscriptionId --registry $ContainerRegistryName `
    --image "$DabImageName`:$deploymentImageTag" --file (Join-Path $dabRoot 'Dockerfile') $dabRoot
if ($LASTEXITCODE -ne 0) { throw 'ACR cloud build failed.' }
Write-Ok "$($registry.loginServer)/$DabImageName`:$deploymentImageTag"

Write-Step "Managed identity $DabIdentityName"
$identity = Invoke-AzJson @('identity', 'show', '--subscription', $ExpectedSubscriptionId,
    '--resource-group', $ResourceGroup, '--name', $DabIdentityName, '--output', 'json') -AllowFailure
if (-not $identity) {
    $identity = Invoke-AzJson @('identity', 'create', '--subscription', $ExpectedSubscriptionId,
        '--resource-group', $ResourceGroup, '--name', $DabIdentityName,
        '--location', $PreferredLocation, '--output', 'json')
}
Write-Ok "$($identity.clientId)"
$connectionString = "Server=tcp:$SqlServerName.database.windows.net,1433;Initial Catalog=$DatabaseName;Authentication=Active Directory Managed Identity;User Id=$($identity.clientId);Encrypt=True;TrustServerCertificate=False;"

Write-Step 'ACR pull permission'
$pullRole = Invoke-AzJson @('role', 'assignment', 'list', '--subscription', $ExpectedSubscriptionId,
    '--assignee-object-id', $identity.principalId, '--scope', $registry.id,
    '--role', 'AcrPull', '--output', 'json')
if (-not $pullRole) {
    Invoke-AzJson @('role', 'assignment', 'create', '--subscription', $ExpectedSubscriptionId,
        '--assignee-object-id', $identity.principalId, '--assignee-principal-type', 'ServicePrincipal',
        '--scope', $registry.id, '--role', 'AcrPull', '--output', 'json') | Out-Null
}
Write-Ok 'AcrPull assigned'

Write-Step 'Least-privilege Azure SQL user'
$python = Get-PythonCommand
& $python (Join-Path $PSScriptRoot '..\database\grant_dab_identity.py') `
    --subscription $ExpectedSubscriptionId `
    --server "$SqlServerName.database.windows.net" `
    --database $DatabaseName `
    --identity-name $DabIdentityName `
    --identity-object-id $identity.principalId `
    --foundry-endpoint "https://$FoundryAccountName.cognitiveservices.azure.com/"
if ($LASTEXITCODE -ne 0) { throw 'DAB database identity grant failed.' }
Write-Ok 'EXECUTE-only role membership verified'

Write-Step "Container Apps environment $ContainerAppsEnvironmentName"
$environment = Invoke-AzJson @('containerapp', 'env', 'show', '--subscription', $ExpectedSubscriptionId,
    '--resource-group', $ResourceGroup, '--name', $ContainerAppsEnvironmentName,
    '--output', 'json') -AllowFailure
if (-not $environment) {
    $environment = Invoke-AzJson @('containerapp', 'env', 'create', '--subscription', $ExpectedSubscriptionId,
        '--resource-group', $ResourceGroup, '--name', $ContainerAppsEnvironmentName,
        '--location', $PreferredLocation, '--output', 'json')
}
Write-Ok 'Ready'

Write-Step "Container app $DabContainerAppName"
$image = "$($registry.loginServer)/$DabImageName`:$deploymentImageTag"
$app = Invoke-AzJson @('containerapp', 'show', '--subscription', $ExpectedSubscriptionId,
    '--resource-group', $ResourceGroup, '--name', $DabContainerAppName, '--output', 'json') -AllowFailure
if (-not $app) {
    $app = Invoke-AzJson @('containerapp', 'create', '--subscription', $ExpectedSubscriptionId,
        '--resource-group', $ResourceGroup, '--name', $DabContainerAppName,
        '--environment', $ContainerAppsEnvironmentName, '--image', $image,
        '--user-assigned', $identity.id, '--registry-server', $registry.loginServer,
        '--registry-identity', $identity.id, '--target-port', '5000', '--ingress', 'external',
        '--transport', 'auto', '--min-replicas', '1', '--max-replicas', '2',
        '--cpu', '0.5', '--memory', '1.0Gi',
        '--env-vars', "SQL_CONNECTION_STRING=$connectionString", "AZURE_CLIENT_ID=$($identity.clientId)",
        '--output', 'json')
}
else {
    $app = Invoke-AzJson @('containerapp', 'update', '--subscription', $ExpectedSubscriptionId,
        '--resource-group', $ResourceGroup, '--name', $DabContainerAppName,
        '--image', $image, '--set-env-vars', "SQL_CONNECTION_STRING=$connectionString", "AZURE_CLIENT_ID=$($identity.clientId)",
        '--output', 'json')
}
$fqdn = $app.properties.configuration.ingress.fqdn
if (-not $fqdn) { throw 'Container App did not return an ingress FQDN.' }
Write-Ok "https://$fqdn/mcp"

Write-Host "`nStage 2 DAB deployment ready for remote contract verification." -ForegroundColor Green
Write-Host "MCP endpoint: https://$fqdn/mcp"
Write-Host 'Next: run 06-verify-dab-container-app.ps1.'
