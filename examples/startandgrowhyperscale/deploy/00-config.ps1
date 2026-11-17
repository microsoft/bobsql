[CmdletBinding()]
param()

$script:SubscriptionId = if ($env:AZURE_SUBSCRIPTION_ID) {
    $env:AZURE_SUBSCRIPTION_ID
}
else {
    (& az account show --query id --output tsv 2>$null)
}
if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
    throw 'Set AZURE_SUBSCRIPTION_ID or sign in with az login before running deployment scripts.'
}

$defaultSuffix = ($SubscriptionId -replace '-', '').Substring(0, 6).ToLowerInvariant()
$script:ResourceGroup = if ($env:CALDOVA_NETWORK_RESOURCE_GROUP) { $env:CALDOVA_NETWORK_RESOURCE_GROUP } else { 'caldova-network-rg' }
$script:AppLocation = if ($env:CALDOVA_NETWORK_APP_LOCATION) { $env:CALDOVA_NETWORK_APP_LOCATION } else { 'eastus2' }
$script:AppServicePlanName = if ($env:CALDOVA_NETWORK_APP_PLAN) { $env:CALDOVA_NETWORK_APP_PLAN } else { "asp-caldova-network-$defaultSuffix" }
$script:AppName = if ($env:CALDOVA_NETWORK_APP_NAME) { $env:CALDOVA_NETWORK_APP_NAME } else { "app-caldova-network-$defaultSuffix" }
$script:AppSku = 'S1'
$script:DemoMode = 'Measured'
$script:AppUrl = "https://$AppName.azurewebsites.net"
$script:SqlLocation = if ($env:CALDOVA_NETWORK_SQL_LOCATION) { $env:CALDOVA_NETWORK_SQL_LOCATION } else { 'eastus2' }
$script:SqlServerName = if ($env:CALDOVA_NETWORK_SQL_SERVER) { $env:CALDOVA_NETWORK_SQL_SERVER } else { "sql-caldova-network-$defaultSuffix" }
$script:SqlServerFqdn = "$SqlServerName.database.windows.net"
# Part 1 uses its own server with the same database name, so its auto-pause cycle never conflicts with Part 2 pool moves.
$script:Part1SqlServerName = if ($env:CALDOVA_PART1_SQL_SERVER) { $env:CALDOVA_PART1_SQL_SERVER } else { "sql-caldova-start-$defaultSuffix" }
$script:Part1SqlServerFqdn = "$Part1SqlServerName.database.windows.net"
$script:ElasticPoolName = 'caldova-network-pool'
$script:ElasticPoolVCores = 8
$script:ElasticPoolMinVCoresPerDatabase = 0
$script:ElasticPoolMaxVCoresPerDatabase = 12
$script:CaldovaDatabase = 'caldova-scheduling'
$script:CaldovaMaxVCores = 8
$script:CaldovaMinVCores = 1
$script:AutoPauseDelayMinutes = 60
$script:AcquiredDatabases = @(
    @{ Name = 'northbrook-scheduling'; VCores = 2 }
    @{ Name = 'ridgeview-scheduling'; VCores = 4 }
)
# Every database and the pool share these so the databases can later move into the pool.
$script:BackupStorageRedundancy = 'Local'
$script:ZoneRedundant = 'false'
$script:AppProject = Join-Path $PSScriptRoot '..\app\CaldovaNetworkScheduling.csproj'
$script:Tags = @(
    'workload=caldova-hyperscale-basics'
    'event=microsoft-mechanics'
    'deployed-by=caldova-demo'
)

function Write-Step { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Ok { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Skip { param([string]$Message) Write-Host "    $Message" -ForegroundColor DarkGray }

function Invoke-Az {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure,
        [switch]$Raw
    )

    $output = & az @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($AllowFailure) { return $null }
        throw "az $($Arguments -join ' ') failed with exit code $LASTEXITCODE`n$($output -join [Environment]::NewLine)"
    }

    $stdout = $output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
    if ($Raw) { return ($stdout | Out-String).Trim() }
    if ([string]::IsNullOrWhiteSpace(($stdout | Out-String))) { return $null }

    $parsed = $stdout | Out-String | ConvertFrom-Json
    if ($parsed -is [pscustomobject] -and @($parsed.PSObject.Properties).Count -eq 0) {
        return $null
    }
    return $parsed
}
