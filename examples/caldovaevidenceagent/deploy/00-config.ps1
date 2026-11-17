[CmdletBinding()]
param()

$accountText = & az account show --output json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $accountText) {
    throw 'Azure CLI is not signed in. Run az login and select the target subscription.'
}
$currentAccount = $accountText | ConvertFrom-Json

$script:ExpectedSubscriptionId = if ($env:CALDOVA_SUBSCRIPTION_ID) { $env:CALDOVA_SUBSCRIPTION_ID } else { $currentAccount.id }
$script:ExpectedTenantId = if ($env:CALDOVA_TENANT_ID) { $env:CALDOVA_TENANT_ID } else { $currentAccount.tenantId }
$script:PreferredLocation = if ($env:CALDOVA_SQL_LOCATION) { $env:CALDOVA_SQL_LOCATION } else { 'westcentralus' }
$script:CandidateLocations = if ($env:CALDOVA_CANDIDATE_LOCATIONS) {
    @($env:CALDOVA_CANDIDATE_LOCATIONS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
} else { @($PreferredLocation, 'eastus2', 'northcentralus', 'swedencentral') | Select-Object -Unique }
$script:FoundryLocation = if ($env:CALDOVA_FOUNDRY_LOCATION) { $env:CALDOVA_FOUNDRY_LOCATION } else { 'eastus2' }
$script:AppLocation = if ($env:CALDOVA_APP_LOCATION) { $env:CALDOVA_APP_LOCATION } else { 'centralus' }

$defaultSuffix = (($ExpectedSubscriptionId -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()).Substring(0, 6)
$script:NameSuffix = if ($env:CALDOVA_NAME_SUFFIX) { $env:CALDOVA_NAME_SUFFIX.ToLowerInvariant() } else { $defaultSuffix }
if ($NameSuffix -notmatch '^[a-z0-9]{3,10}$') { throw 'CALDOVA_NAME_SUFFIX must contain 3-10 lowercase letters or numbers.' }
$script:ResourceGroup = if ($env:CALDOVA_RESOURCE_GROUP) { $env:CALDOVA_RESOURCE_GROUP } else { 'rg-caldova-evidence' }
$script:SqlServerName = "sql-caldova-evidence-$NameSuffix"
$script:DatabaseName = 'research'
$script:DatabaseServiceObjective = 'HS_S_Gen5_2'
$script:DatabaseMinCapacity = 0.5
$script:FoundryAccountName = "ai-caldova-evidence-$NameSuffix"
$script:FoundryProjectName = 'caldova-evidence-agent'
$script:FoundryProjectEndpoint = "https://$FoundryAccountName.services.ai.azure.com/api/projects/$FoundryProjectName"
$script:EmbeddingModelName = 'text-embedding-3-small'
$script:EmbeddingDeploymentName = 'text-embedding-3-small'
$script:EmbeddingDeploymentCapacity = 50
$script:EmbeddingDimensions = 512
$script:ChatModelName = 'gpt-5'
$script:ChatDeploymentName = 'gpt-5'
$script:ChatModelVersion = '2025-08-07'
$script:ChatDeploymentCapacity = 1000
$script:HostedAgentName = 'caldova-evidence-hosted'
$script:SkillName = 'biomedical-evidence-review-v2'
$script:AzdEnvironmentName = if ($env:CALDOVA_AZD_ENVIRONMENT) { $env:CALDOVA_AZD_ENVIRONMENT } else { 'caldova-evidence' }
$script:ContainerRegistryName = "caldovaevidence$NameSuffix"
$script:ContainerAppsEnvironmentName = "cae-caldova-evidence-$NameSuffix"
$script:DabContainerAppName = "ca-caldova-evidence-mcp-$NameSuffix"
$script:DabIdentityName = "id-caldova-evidence-mcp-$NameSuffix"
$script:DabImageName = 'caldova-evidence-dab'
$script:DabImageTag = '2.0.9'
$script:BootstrapFirewallRuleName = 'BootstrapClient'
$script:CorpusPath = Join-Path $PSScriptRoot '..\corpus\pmc-curated-v1'
$script:AppServicePlanName = "asp-caldova-evidence-$NameSuffix"
$script:AppServiceName = "app-caldova-evidence-$NameSuffix"
$script:AppIdentityName = "id-caldova-evidence-app-$NameSuffix"
$script:AppInsightsName = "appi-caldova-evidence-$NameSuffix"

$script:Tags = @(
    'workload=caldova-evidence-agent'
    "deployed-by=$($currentAccount.user.name)"
)

function Write-Step { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Ok { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "    $Message" -ForegroundColor Yellow }

function Invoke-AzJson {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $output = & az @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($AllowFailure) { return $null }
        throw "az $($Arguments -join ' ') failed with exit code $LASTEXITCODE`n$($output -join [Environment]::NewLine)"
    }

    $text = ($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json
}

function Get-CurrentClientIp {
    return (Invoke-RestMethod -Uri 'https://api.ipify.org').Trim()
}

function Get-PythonCommand {
    $workspacePython = Join-Path $PSScriptRoot '..\.venv\Scripts\python.exe'
    if (Test-Path $workspacePython) { return (Resolve-Path $workspacePython).Path }
    return (Get-Command python -ErrorAction Stop).Source
}
