[CmdletBinding()]
param()

if ([string]::IsNullOrWhiteSpace($env:AZURE_SUBSCRIPTION_ID)) {
    throw 'Set AZURE_SUBSCRIPTION_ID before running deployment scripts.'
}

$script:SubscriptionId = $env:AZURE_SUBSCRIPTION_ID
$defaultSuffix = ($SubscriptionId -replace '-', '').Substring(0, 6).ToLowerInvariant()
$script:ResourceGroup = if ($env:CALDOVA_RESOURCE_GROUP) { $env:CALDOVA_RESOURCE_GROUP } else { 'rg-caldova-handsfree-indexing' }
$script:Location = if ($env:CALDOVA_SQL_LOCATION) { $env:CALDOVA_SQL_LOCATION } else { 'eastus' }
$script:AppLocation = if ($env:CALDOVA_APP_LOCATION) { $env:CALDOVA_APP_LOCATION } else { 'eastus2' }
$script:SqlServerName = if ($env:CALDOVA_SQL_SERVER) { $env:CALDOVA_SQL_SERVER } else { "sql-caldova-hfi-$defaultSuffix" }
$script:DatabaseName = if ($env:CALDOVA_DATABASE) { $env:CALDOVA_DATABASE } else { 'caldova-hfi' }
$script:DatabaseVCoreCapacity = if ($env:CALDOVA_SQL_VCORES) { [int]$env:CALDOVA_SQL_VCORES } else { 4 }
$script:DatabaseServiceObjective = "HS_Gen5_$DatabaseVCoreCapacity"
$script:AppServicePlanName = if ($env:CALDOVA_APP_PLAN) { $env:CALDOVA_APP_PLAN } else { "asp-caldova-hfi-$defaultSuffix" }
$script:AppName = if ($env:CALDOVA_APP_NAME) { $env:CALDOVA_APP_NAME } else { "app-caldova-hfi-$defaultSuffix" }
$script:VirtualNetworkName = "vnet-caldova-hfi-$defaultSuffix"
$script:AppVirtualNetworkName = "vnet-caldova-hfi-app-$defaultSuffix"
$script:AppSubnetName = 'snet-app-integration'
$script:PrivateEndpointSubnetName = 'snet-private-endpoints'
$script:SqlToAppPeeringName = 'peer-sql-to-app'
$script:AppToSqlPeeringName = 'peer-app-to-sql'
$script:PrivateEndpointName = "pe-sql-caldova-hfi-$defaultSuffix"
$script:PrivateDnsZoneName = 'privatelink.database.windows.net'
$script:PrivateDnsLinkName = 'link-caldova-hfi-vnet'
$script:AppPrivateDnsLinkName = 'link-caldova-hfi-app-vnet'
$script:PrivateDnsZoneGroupName = 'sql-dns'
$script:BootstrapFirewallRuleName = 'BootstrapClient'
$script:SqlServerFqdn = "$SqlServerName.database.windows.net"
$script:AppUrl = "https://$AppName.azurewebsites.net"
$script:AppProject = Join-Path $PSScriptRoot '..\app\CaldovaPatientAccessOps.csproj'
$script:Tags = @(
    'workload=caldova-handsfree-indexing'
    'event=sqlcon-europe-2026'
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

function Get-CurrentClientIp {
    return (Invoke-RestMethod -Uri 'https://api.ipify.org').Trim()
}

function Invoke-DemoSqlFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$TimeoutSeconds = 1200
    )

    $sqlcmd = Get-Command sqlcmd -ErrorAction Stop
    & $sqlcmd.Source `
        -S $SqlServerFqdn `
        -d $DatabaseName `
        --authentication-method ActiveDirectoryDefault `
        -N strict `
        -b `
        -t $TimeoutSeconds `
        -i $Path

    if ($LASTEXITCODE -ne 0) {
        throw "SQL execution failed for $Path."
    }
}
