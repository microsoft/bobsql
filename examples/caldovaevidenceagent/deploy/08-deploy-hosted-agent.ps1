[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\00-config.ps1"

$agentRoot = Resolve-Path (Join-Path $PSScriptRoot '..\agent\hosted\caldova-evidence-hosted')
$skillPath = Join-Path $agentRoot 'skills\biomedical-evidence-review\SKILL.md'
$account = Invoke-AzJson @('account', 'show', '--output', 'json')
if ($account.id -ne $ExpectedSubscriptionId -or $account.tenantId -ne $ExpectedTenantId) {
    throw 'Azure CLI context changed after pre-flight.'
}
if (-not (Get-Command azd -ErrorAction SilentlyContinue)) { throw 'Azure Developer CLI (azd) is required.' }

$project = Invoke-AzJson @('cognitiveservices', 'account', 'project', 'show',
    '--subscription', $ExpectedSubscriptionId, '--resource-group', $ResourceGroup,
    '--name', $FoundryAccountName, '--project-name', $FoundryProjectName, '--output', 'json')
$fqdn = & az containerapp show --subscription $ExpectedSubscriptionId --resource-group $ResourceGroup `
    --name $DabContainerAppName --query properties.configuration.ingress.fqdn --output tsv
if ($LASTEXITCODE -ne 0 -or -not $fqdn) { throw 'Could not resolve the DAB MCP endpoint.' }
$mcpEndpoint = "https://$fqdn/mcp"

Push-Location $agentRoot
try {
    $env:AZURE_DEV_USER_AGENT = 'caldova_evidence_agent_publish'
    & azd env select $AzdEnvironmentName 2>$null
    if ($LASTEXITCODE -ne 0) {
        & azd env new $AzdEnvironmentName --no-prompt
        if ($LASTEXITCODE -ne 0) { throw "Could not create azd environment $AzdEnvironmentName." }
    }

    $settings = [ordered]@{
        FOUNDRY_PROJECT_ENDPOINT = $FoundryProjectEndpoint
        AZURE_AI_PROJECT_ENDPOINT = $FoundryProjectEndpoint
        AZURE_AI_PROJECT_ID = $project.id
        AZURE_AI_MODEL_DEPLOYMENT_NAME = $ChatDeploymentName
        AZURE_SUBSCRIPTION_ID = $ExpectedSubscriptionId
        AZURE_TENANT_ID = $ExpectedTenantId
        AZURE_RESOURCE_GROUP = $ResourceGroup
        SKILL_NAMES = $SkillName
        SQL_MCP_ENDPOINT = $mcpEndpoint
    }
    foreach ($entry in $settings.GetEnumerator()) {
        & azd env set $entry.Key ([string]$entry.Value)
        if ($LASTEXITCODE -ne 0) { throw "Could not set azd environment value $($entry.Key)." }
    }
    & azd ai project set $FoundryProjectEndpoint
    if ($LASTEXITCODE -ne 0) { throw 'Could not select the Foundry project.' }

    & azd ai skill show $SkillName --output json --no-prompt *> $null
    if ($LASTEXITCODE -eq 0) {
        & azd ai skill update $SkillName --file $skillPath --no-prompt
    } else {
        & azd ai skill create $SkillName --file $skillPath --no-prompt
    }
    if ($LASTEXITCODE -ne 0) { throw 'Foundry skill publication failed.' }

    & azd deploy $HostedAgentName --no-prompt
    if ($LASTEXITCODE -ne 0) { throw 'Hosted agent deployment failed.' }
    $agent = & azd ai agent show $HostedAgentName --environment $AzdEnvironmentName --output json | ConvertFrom-Json
    if ($agent.status -ne 'active') { throw "Hosted agent status is $($agent.status)." }
    Write-Host "`nHosted agent ready." -ForegroundColor Green
    Write-Host "Agent:    $HostedAgentName version $($agent.version)"
    Write-Host "Skill:    $SkillName"
    Write-Host "SQL MCP:  $mcpEndpoint"
} finally {
    Pop-Location
}
