[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\00-config.ps1"

$appRoot = Resolve-Path (Join-Path $PSScriptRoot '..\app')
$agentRoot = Resolve-Path (Join-Path $PSScriptRoot '..\agent\hosted\caldova-evidence-hosted')
$account = Invoke-AzJson @('account', 'show', '--output', 'json')
$registry = Invoke-AzJson @('acr', 'show', '--subscription', $ExpectedSubscriptionId,
    '--resource-group', $ResourceGroup, '--name', $ContainerRegistryName, '--output', 'json')
$workspaceId = & az monitor log-analytics workspace list --subscription $ExpectedSubscriptionId `
    --resource-group $ResourceGroup --query '[0].id' --output tsv
if ($LASTEXITCODE -ne 0 -or -not $workspaceId) { throw 'No Log Analytics workspace was found in the resource group.' }

Push-Location $agentRoot
try {
    $env:AZURE_DEV_USER_AGENT = 'caldova_evidence_agent_publish'
    $agent = & azd ai agent show $HostedAgentName --environment $AzdEnvironmentName --output json | ConvertFrom-Json
    if ($agent.status -ne 'active') { throw "Hosted agent status is $($agent.status)." }
} finally {
    Pop-Location
}

$imageTag = Get-Date -Format 'yyyyMMddHHmmss'
$imageName = "caldova-evidence-app:$imageTag"
Write-Step "Build application image $imageName"
& az acr build --subscription $ExpectedSubscriptionId --registry $ContainerRegistryName `
    --image $imageName --file (Join-Path $appRoot 'Dockerfile') $appRoot
if ($LASTEXITCODE -ne 0) { throw 'Application ACR build failed.' }
$containerImage = "$($registry.loginServer)/$imageName"
$agentEndpoint = "$FoundryProjectEndpoint/agents/$HostedAgentName/endpoint/protocols/openai/responses?api-version=v1"
$deploymentName = "caldova-evidence-app-$imageTag"
$deploymentParameters = @(
    "environmentName=caldova-evidence-$NameSuffix"
    "location=$AppLocation"
    "sessionId=$([guid]::NewGuid())"
    "deployedBy=$($account.user.name)"
    "createdAt=$((Get-Date).ToString('o'))"
    'deployerObjectId='
    "resourceGroupName=$ResourceGroup"
    "appServicePlanName=$AppServicePlanName"
    "appServiceName=$AppServiceName"
    "managedIdentityName=$AppIdentityName"
    "appInsightsName=$AppInsightsName"
    "containerImage=$containerImage"
    "acrName=$ContainerRegistryName"
    "acrLoginServer=$($registry.loginServer)"
    "foundryAccountName=$FoundryAccountName"
    "logAnalyticsWorkspaceId=$workspaceId"
    "agentEndpoint=$agentEndpoint"
    "agentName=$HostedAgentName"
    "agentVersion=$($agent.version)"
)

Write-Step "Deploy App Service $AppServiceName"
& az deployment sub create --subscription $ExpectedSubscriptionId --name $deploymentName `
    --location $AppLocation --template-file (Join-Path $appRoot 'infra\main.bicep') `
    --parameters $deploymentParameters --output none
if ($LASTEXITCODE -ne 0) { throw 'App Service deployment failed.' }

& az webapp restart --subscription $ExpectedSubscriptionId --resource-group $ResourceGroup --name $AppServiceName
if ($LASTEXITCODE -ne 0) { throw 'App Service restart failed.' }
Write-Host "`nApplication ready." -ForegroundColor Green
Write-Host "URL: https://$AppServiceName.azurewebsites.net/"
Write-Host "Agent: $HostedAgentName version $($agent.version)"
