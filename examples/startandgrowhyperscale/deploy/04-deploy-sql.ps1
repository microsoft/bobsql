[CmdletBinding()]
param(
    [string]$ClientIp
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId, '--output', 'none') | Out-Null

Write-Step "Resource group $ResourceGroup"
$exists = Invoke-Az @('group', 'exists', '--name', $ResourceGroup, '--output', 'tsv') -Raw
if ($exists -ne 'true') {
    Invoke-Az (@('group', 'create', '--name', $ResourceGroup, '--location', $AppLocation, '--tags') + $Tags + @('--output', 'json')) | Out-Null
    Write-Ok 'Created'
}
else { Write-Skip 'Already exists' }

Write-Step "Logical server $SqlServerName ($SqlLocation)"
$server = Invoke-Az @('sql', 'server', 'show', '--resource-group', $ResourceGroup, '--name', $SqlServerName, '--output', 'json') -AllowFailure
if (-not $server) {
    $signedInUser = Invoke-Az @('ad', 'signed-in-user', 'show', '--output', 'json')
    $server = Invoke-Az (@('sql', 'server', 'create', '--resource-group', $ResourceGroup, '--name', $SqlServerName,
        '--location', $SqlLocation, '--enable-ad-only-auth', '--external-admin-principal-type', 'User',
        '--external-admin-name', $signedInUser.userPrincipalName, '--external-admin-sid', $signedInUser.id,
        '--assign-identity', '--minimal-tls-version', '1.2', '--enable-public-network', 'true',
        '--tags') + $Tags + @('--output', 'json'))
    Write-Ok "Created (Microsoft Entra-only; admin $($signedInUser.userPrincipalName))"
}
else { Write-Skip 'Already exists' }
if (($server.location -replace '\s', '') -ne $SqlLocation) {
    throw "$SqlServerName exists in $($server.location), not $SqlLocation."
}

if (-not $ClientIp) { $ClientIp = (Invoke-RestMethod -Uri 'https://api.ipify.org').Trim() }
Write-Step "Firewall rule for this client ($ClientIp)"
Invoke-Az @('sql', 'server', 'firewall-rule', 'create', '--resource-group', $ResourceGroup,
    '--server', $SqlServerName, '--name', 'PresenterClient', '--start-ip-address', $ClientIp,
    '--end-ip-address', $ClientIp, '--output', 'json') | Out-Null
Write-Ok 'PresenterClient rule set'

function New-DemoDatabase {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$ComputeArguments,
        [Parameter(Mandatory)][string]$Description
    )

    Write-Step "Database $Name ($Description)"
    $database = Invoke-Az @('sql', 'db', 'show', '--resource-group', $ResourceGroup, '--server', $SqlServerName,
        '--name', $Name, '--output', 'json') -AllowFailure
    if ($database) { Write-Skip 'Already exists'; return }

    Invoke-Az (@('sql', 'db', 'create', '--resource-group', $ResourceGroup, '--server', $SqlServerName,
        '--name', $Name, '--edition', 'Hyperscale', '--family', 'Gen5') + $ComputeArguments + @(
        '--backup-storage-redundancy', $BackupStorageRedundancy, '--zone-redundant', $ZoneRedundant,
        '--tags') + $Tags + @('--output', 'json')) | Out-Null
    Write-Ok 'Created'
}

New-DemoDatabase -Name $CaldovaDatabase -Description "serverless HS_S_Gen5_$CaldovaMaxVCores, auto-pause $AutoPauseDelayMinutes min" -ComputeArguments @(
    '--compute-model', 'Serverless', '--capacity', "$CaldovaMaxVCores", '--min-capacity', "$CaldovaMinVCores",
    '--auto-pause-delay', "$AutoPauseDelayMinutes")

foreach ($acquired in $AcquiredDatabases) {
    New-DemoDatabase -Name $acquired.Name -Description "provisioned HS_Gen5_$($acquired.VCores)" -ComputeArguments @(
        '--compute-model', 'Provisioned', '--capacity', "$($acquired.VCores)")
}

Write-Step "Hyperscale elastic pool $ElasticPoolName ($ElasticPoolVCores vCores, empty)"
$pool = Invoke-Az @('sql', 'elastic-pool', 'show', '--resource-group', $ResourceGroup, '--server', $SqlServerName,
    '--name', $ElasticPoolName, '--output', 'json') -AllowFailure
if (-not $pool) {
    Invoke-Az (@('sql', 'elastic-pool', 'create', '--resource-group', $ResourceGroup, '--server', $SqlServerName,
        '--name', $ElasticPoolName, '--edition', 'Hyperscale', '--family', 'Gen5', '--capacity', "$ElasticPoolVCores",
        '--db-min-capacity', "$ElasticPoolMinVCoresPerDatabase",
        '--db-max-capacity', "$([Math]::Min($ElasticPoolVCores, $ElasticPoolMaxVCoresPerDatabase))",
        '--zone-redundant', $ZoneRedundant, '--tags') + $Tags + @('--output', 'json')) | Out-Null
    Write-Ok 'Created'
    $pool = Invoke-Az @('sql', 'elastic-pool', 'show', '--resource-group', $ResourceGroup, '--server', $SqlServerName,
        '--name', $ElasticPoolName, '--output', 'json')
}
else { Write-Skip 'Already exists' }

$expectedMax = [Math]::Min($pool.sku.capacity, $ElasticPoolMaxVCoresPerDatabase)
if ($pool.perDatabaseSettings.minCapacity -ne $ElasticPoolMinVCoresPerDatabase -or
    $pool.perDatabaseSettings.maxCapacity -ne $expectedMax) {
    throw "$ElasticPoolName requires per-database limits $ElasticPoolMinVCoresPerDatabase-$expectedMax at $($pool.sku.capacity) pool vCores. Inspect the pool and approve a separate limit change; do not recreate it."
}

Write-Host "`nSQL ready on $SqlServerFqdn ($SqlLocation). Databases are standalone; the pool is empty." -ForegroundColor Green
Write-Host 'Next: run 05-verify-sql.ps1.'
