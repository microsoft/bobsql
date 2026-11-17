[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\00-config.ps1"

Write-Host 'Caldova Evidence Agent: Stage 3 Foundry infrastructure' -ForegroundColor Cyan
$account = Invoke-AzJson @('account', 'show', '--output', 'json')
if ($account.id -ne $ExpectedSubscriptionId -or $account.tenantId -ne $ExpectedTenantId) {
    throw 'Azure CLI is not using the approved subscription and tenant.'
}

Write-Step "Foundry project $FoundryProjectName"
$projects = Invoke-AzJson @('cognitiveservices', 'account', 'project', 'list',
    '--subscription', $ExpectedSubscriptionId, '--resource-group', $ResourceGroup,
    '--name', $FoundryAccountName, '--output', 'json')
$project = @($projects | Where-Object name -eq $FoundryProjectName) | Select-Object -First 1
if (-not $project) {
    $project = Invoke-AzJson @('cognitiveservices', 'account', 'project', 'create',
        '--subscription', $ExpectedSubscriptionId, '--resource-group', $ResourceGroup,
        '--name', $FoundryAccountName, '--project-name', $FoundryProjectName,
        '--location', $FoundryLocation, '--display-name', 'Caldova Evidence Agent',
        '--description', 'Conversational biomedical evidence investigation over governed Azure SQL MCP tools.',
        '--assign-identity', '--output', 'json')
}
Write-Ok "$($project.name), $FoundryProjectEndpoint"

Write-Step "GPT-5 deployment $ChatDeploymentName"
$deployment = Invoke-AzJson @('cognitiveservices', 'account', 'deployment', 'show',
    '--subscription', $ExpectedSubscriptionId, '--resource-group', $ResourceGroup,
    '--name', $FoundryAccountName, '--deployment-name', $ChatDeploymentName,
    '--output', 'json') -AllowFailure
if (-not $deployment -or $deployment.sku.capacity -ne $ChatDeploymentCapacity) {
    $deployment = Invoke-AzJson @('cognitiveservices', 'account', 'deployment', 'create',
        '--subscription', $ExpectedSubscriptionId, '--resource-group', $ResourceGroup,
        '--name', $FoundryAccountName, '--deployment-name', $ChatDeploymentName,
        '--model-name', $ChatModelName, '--model-version', $ChatModelVersion,
        '--model-format', 'OpenAI', '--sku-name', 'GlobalStandard',
        '--sku-capacity', $ChatDeploymentCapacity, '--output', 'json')
}
if ($deployment.properties.provisioningState -ne 'Succeeded') {
    throw "GPT-5 deployment state is $($deployment.properties.provisioningState)."
}
Write-Ok "$($deployment.properties.model.name) $($deployment.properties.model.version), $($deployment.sku.name) capacity $($deployment.sku.capacity)"

Write-Host "`nFoundry infrastructure ready." -ForegroundColor Green
Write-Host "Project endpoint: $FoundryProjectEndpoint"
Write-Host "Model deployment: $ChatDeploymentName"
Write-Host 'Next: run 08-deploy-hosted-agent.ps1.'