[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$ClientIp,
    [switch]$AllowAzureServices,
    [double]$MinVCores,
    [int]$MaxVCores,
    [int]$AutoPauseDelay
)

# Deploys the separate Part 1 serverless database: same database name as Part 2
# (caldova-scheduling) on its own logical server. Part 2's server and pool are not touched.
# Run with -WhatIf first to print the exact plan without creating anything.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"

if (-not $PSBoundParameters.ContainsKey('MinVCores')) { $MinVCores = $CaldovaMinVCores }
if (-not $PSBoundParameters.ContainsKey('MaxVCores')) { $MaxVCores = $CaldovaMaxVCores }
if (-not $PSBoundParameters.ContainsKey('AutoPauseDelay')) { $AutoPauseDelay = $AutoPauseDelayMinutes }
if ($AutoPauseDelay -ne -1 -and $AutoPauseDelay -lt 60) {
    throw 'Hyperscale serverless auto-pause delay must be at least 60 minutes, or -1 to disable it.'
}
if ($MinVCores -le 0 -or $MinVCores -gt $MaxVCores) { throw "Minimum vCores ($MinVCores) must be above 0 and no more than maximum ($MaxVCores)." }

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId, '--output', 'none') | Out-Null
if (-not $ClientIp -and -not $AllowAzureServices) { $ClientIp = (Invoke-RestMethod -Uri 'https://api.ipify.org').Trim() }
$objective = "HS_S_Gen5_$MaxVCores"
$autoPauseText = if ($AutoPauseDelay -eq -1) { 'disabled' } else { "$AutoPauseDelay min" }

Write-Step 'Plan'
[pscustomobject]@{
    Subscription      = $SubscriptionId
    ResourceGroup     = $ResourceGroup
    Region            = $SqlLocation
    Server            = "$Part1SqlServerFqdn (Microsoft Entra-only authentication, TLS 1.2)"
    Database          = $CaldovaDatabase
    Compute           = "Hyperscale serverless $objective, $MinVCores-$MaxVCores vCores"
    AutoPause         = $autoPauseText
    BackupRedundancy  = $BackupStorageRedundancy
    ZoneRedundant     = $ZoneRedundant
    Firewall          = (@($(if ($ClientIp) { "PresenterClient $ClientIp" }), $(if ($AllowAzureServices) { 'Allow Azure services' })) | Where-Object { $_ }) -join '; '
} | Format-List | Out-String | Write-Host

Write-Step "Logical server $Part1SqlServerName ($SqlLocation)"
$server = Invoke-Az @('sql', 'server', 'show', '--resource-group', $ResourceGroup, '--name', $Part1SqlServerName, '--output', 'json') -AllowFailure
if ($server) {
    Write-Skip 'Already exists'
    if (($server.location -replace '\s', '') -ne $SqlLocation) {
        throw "$Part1SqlServerName exists in $($server.location), not $SqlLocation."
    }
}
elseif ($PSCmdlet.ShouldProcess($Part1SqlServerFqdn, 'Create logical server (Microsoft Entra-only)')) {
    $signedInUser = Invoke-Az @('ad', 'signed-in-user', 'show', '--output', 'json')
    $server = Invoke-Az (@('sql', 'server', 'create', '--resource-group', $ResourceGroup, '--name', $Part1SqlServerName,
        '--location', $SqlLocation, '--enable-ad-only-auth', '--external-admin-principal-type', 'User',
        '--external-admin-name', $signedInUser.userPrincipalName, '--external-admin-sid', $signedInUser.id,
        '--assign-identity', '--minimal-tls-version', '1.2', '--enable-public-network', 'true',
        '--tags') + $Tags + @('part=start', '--output', 'json'))
    Write-Ok "Created (Microsoft Entra-only; admin $($signedInUser.userPrincipalName))"
}

if ($ClientIp -and $PSCmdlet.ShouldProcess($Part1SqlServerFqdn, "Firewall rule PresenterClient = $ClientIp")) {
    Invoke-Az @('sql', 'server', 'firewall-rule', 'create', '--resource-group', $ResourceGroup,
        '--server', $Part1SqlServerName, '--name', 'PresenterClient', '--start-ip-address', $ClientIp,
        '--end-ip-address', $ClientIp, '--output', 'json') | Out-Null
    Write-Ok "PresenterClient rule set ($ClientIp)"
}

# Needed when the presenting machine is Azure-hosted and its outbound IP changes per connection.
if ($AllowAzureServices -and $PSCmdlet.ShouldProcess($Part1SqlServerFqdn, 'Allow Azure services')) {
    Invoke-Az @('sql', 'server', 'firewall-rule', 'create', '--resource-group', $ResourceGroup,
        '--server', $Part1SqlServerName, '--name', 'AllowAllWindowsAzureIps', '--start-ip-address', '0.0.0.0',
        '--end-ip-address', '0.0.0.0', '--output', 'json') | Out-Null
    Write-Ok 'Allow Azure services enabled'
}

Write-Step "Database $CaldovaDatabase ($objective, $MinVCores-$MaxVCores vCores, auto-pause $autoPauseText)"
$database = if ($server) {
    Invoke-Az @('sql', 'db', 'show', '--resource-group', $ResourceGroup, '--server', $Part1SqlServerName,
        '--name', $CaldovaDatabase, '--output', 'json') -AllowFailure
}
if ($database) { Write-Skip 'Already exists' }
elseif ($PSCmdlet.ShouldProcess("$Part1SqlServerFqdn/$CaldovaDatabase", "Create Hyperscale serverless database $objective")) {
    Invoke-Az (@('sql', 'db', 'create', '--resource-group', $ResourceGroup, '--server', $Part1SqlServerName,
        '--name', $CaldovaDatabase, '--edition', 'Hyperscale', '--family', 'Gen5', '--compute-model', 'Serverless',
        '--capacity', "$MaxVCores", '--min-capacity', "$MinVCores", '--auto-pause-delay', "$AutoPauseDelay",
        '--backup-storage-redundancy', $BackupStorageRedundancy, '--zone-redundant', $ZoneRedundant,
        '--tags') + $Tags + @('part=start', '--output', 'json')) | Out-Null
    $database = Invoke-Az @('sql', 'db', 'show', '--resource-group', $ResourceGroup, '--server', $Part1SqlServerName,
        '--name', $CaldovaDatabase, '--output', 'json')
    Write-Ok 'Created'
}

if ($WhatIfPreference) {
    Write-Host "`nPlan only (-WhatIf): nothing was created or changed." -ForegroundColor Yellow
    return
}

Write-Step 'Verify'
if ($database.currentServiceObjectiveName -ne $objective -or [double]$database.minCapacity -ne $MinVCores -or
    $database.autoPauseDelay -ne $AutoPauseDelay) {
    throw "Database exists but does not match the plan: $($database.currentServiceObjectiveName), min $($database.minCapacity), auto-pause $($database.autoPauseDelay)."
}
[pscustomobject]@{
    Database  = "$Part1SqlServerFqdn/$($database.name)"
    Status    = $database.status
    Objective = $database.currentServiceObjectiveName
    MinVCores = $database.minCapacity
    AutoPause = $database.autoPauseDelay
} | Format-List | Out-String | Write-Host

$resourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Sql/servers/$Part1SqlServerName/databases/$CaldovaDatabase"
Write-Ok 'Part 1 database matches the plan. The Part 1 workload uses only DMVs; no schema is required.'
Write-Host 'Run the app for Part 1 with: dotnet run --launch-profile part1   (http://localhost:5099)'
Write-Host "The part1 launch profile targets $resourceId"
