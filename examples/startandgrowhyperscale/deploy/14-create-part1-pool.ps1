[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExpectedServerName
)

$ErrorActionPreference = 'Stop'
try {
    . "$PSScriptRoot\00-config.ps1"
    if ($ExpectedServerName -ne $Part1SqlServerName -or $Part1SqlServerName -eq $SqlServerName -or
        $Part1SqlServerName -notlike 'sql-caldova-start-*') {
        throw 'The expected server must match the configured Start server and must not be Grow.'
    }
    if ($ElasticPoolVCores -notin @(8, 24) -or $ElasticPoolMinVCoresPerDatabase -ne 0 -or
        $BackupStorageRedundancy -ne 'Local' -or $ZoneRedundant -ne 'false') {
        throw 'This workflow requires an 8/24-vCore pool, minimum zero, local database backups, and no zone redundancy.'
    }
    $maximum = [Math]::Min($ElasticPoolVCores, $ElasticPoolMaxVCoresPerDatabase)
    if ($maximum -ne [Math]::Min($ElasticPoolVCores, 12)) {
        throw 'Configured per-database maximum does not match the demo cap policy.'
    }
    $account = Invoke-Az @('account', 'show', '--output', 'json')
    if ($account.id -ne $SubscriptionId -or $account.state -ne 'Enabled' -or -not $account.name) {
        throw 'The current Azure CLI subscription does not match the configured target. No subscription was switched.'
    }
    $user = Invoke-Az @('ad', 'signed-in-user', 'show', '--query', '{id:id}', '--output', 'json')
    if (-not $user.id) { throw 'A currently signed-in Entra user is required.' }

    $serverId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Sql/servers/$Part1SqlServerName"
    $poolId = "$serverId/elasticPools/$ElasticPoolName"
    $server = Invoke-Az @('sql', 'server', 'show', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroup, '--name', $Part1SqlServerName, '--output', 'json')
    if ($server.id -ne $serverId -or ($server.location -replace '\s', '') -ne $SqlLocation -or
        $server.state -ne 'Ready' -or $server.minimalTlsVersion -ne '1.2' -or $server.publicNetworkAccess -ne 'Enabled') {
        throw 'The existing Start server must match the target/region and be Ready with TLS 1.2 and its public endpoint enabled.'
    }
    $auth = Invoke-Az @('sql', 'server', 'ad-only-auth', 'get', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroup, '--name', $Part1SqlServerName, '--output', 'json')
    if ($auth.azureAdOnlyAuthentication -ne $true) { throw 'The Start server must retain Entra-only authentication.' }
    $rules = @(Invoke-Az @('sql', 'server', 'firewall-rule', 'list', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroup, '--server', $Part1SqlServerName, '--output', 'json'))
    if (-not ($rules | Where-Object { $_.startIpAddress -eq '0.0.0.0' -and $_.endIpAddress -eq '0.0.0.0' })) {
        throw 'The approved Allow Azure services rule must already exist. No firewall rules were changed.'
    }

    function Assert-Part1Pool {
        param($Pool)
        if ($Pool.id -ne $poolId -or ($Pool.location -replace '\s', '') -ne $SqlLocation -or
            $Pool.state -ne 'Ready' -or $Pool.sku.tier -ne 'Hyperscale' -or $Pool.sku.family -ne 'Gen5' -or
            $Pool.sku.capacity -ne $ElasticPoolVCores -or $Pool.zoneRedundant -ne $false -or
            $null -eq $Pool.perDatabaseSettings.minCapacity -or $Pool.perDatabaseSettings.minCapacity -ne 0 -or
            $Pool.perDatabaseSettings.maxCapacity -ne $maximum) {
            throw 'The pool does not match the approved identity, Ready state, Hyperscale Gen5 capacity, caps, or redundancy. Inspect partial state and approve any separate change; do not recreate it.'
        }
    }

    $databases = @(Invoke-Az @('sql', 'db', 'list', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroup, '--server', $Part1SqlServerName, '--output', 'json'))
    foreach ($name in @($CaldovaDatabase) + @($AcquiredDatabases | ForEach-Object { $_.Name })) {
        $database = @($databases | Where-Object { $_.name -eq $name })
        if ($database.Count -ne 1 -or $database[0].id -ne "$serverId/databases/$name" -or
            $database[0].status -notin @('Online', 'Paused') -or $database[0].sku.tier -ne 'Hyperscale' -or
            $database[0].requestedBackupStorageRedundancy -ne $BackupStorageRedundancy -or
            $database[0].zoneRedundant -ne $false -or
            ($database[0].elasticPoolId -and $database[0].elasticPoolId -ne $poolId)) {
            throw "Database $name must already exist on Start with compatible Hyperscale/local-backup/non-zone-redundant settings and no other pool. No database was changed."
        }
    }
    $pools = @(Invoke-Az @('sql', 'elastic-pool', 'list', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroup, '--server', $Part1SqlServerName, '--output', 'json'))
    $pool = $pools | Where-Object { $_.name -eq $ElasticPoolName }
    if ($pool) { Assert-Part1Pool $pool }

    Write-Step 'Start pool-only plan'
    [pscustomobject]@{
        Subscription = $account.name
        ResourceGroup = $ResourceGroup
        Server = $Part1SqlServerName
        Pool = "$ElasticPoolName ($(if ($pool) { 'reuse; no changes' } else { 'create empty' }))"
        Region = $SqlLocation
        Compute = "Hyperscale Gen5; $ElasticPoolVCores pool vCores; $ElasticPoolMinVCoresPerDatabase-$maximum per database"
        Availability = 'No zone redundancy; existing local database backups unchanged'
        Security = 'Existing Entra-only, TLS 1.2, and Allow Azure services retained'
        Excluded = 'No database moves/creation/population, preview-setting changes, app changes, or Grow changes'
    } | Format-List | Out-String | Write-Host

    if (-not $pool -and $PSCmdlet.ShouldProcess("$Part1SqlServerName/$ElasticPoolName", 'Create empty Hyperscale elastic pool')) {
        Invoke-Az (@('sql', 'elastic-pool', 'create', '--subscription', $SubscriptionId,
            '--resource-group', $ResourceGroup, '--server', $Part1SqlServerName, '--name', $ElasticPoolName,
            '--edition', 'Hyperscale', '--family', 'Gen5', '--capacity', "$ElasticPoolVCores",
            '--db-min-capacity', "$ElasticPoolMinVCoresPerDatabase", '--db-max-capacity', "$maximum",
            '--zone-redundant', $ZoneRedundant, '--tags') + $Tags + @('part=start', '--output', 'json')) | Out-Null
        $pool = Invoke-Az @('sql', 'elastic-pool', 'show', '--subscription', $SubscriptionId,
            '--resource-group', $ResourceGroup, '--server', $Part1SqlServerName,
            '--name', $ElasticPoolName, '--output', 'json')
        Assert-Part1Pool $pool
        $after = @(Invoke-Az @('sql', 'db', 'list', '--subscription', $SubscriptionId,
            '--resource-group', $ResourceGroup, '--server', $Part1SqlServerName, '--output', 'json'))
        if ($after | Where-Object { $_.elasticPoolId -eq $poolId }) {
            throw 'The new pool has database members unexpectedly. Inspect partial state; no automatic corrective action was taken.'
        }
    }
    if ($WhatIfPreference) {
        Write-Host 'Plan only: no Azure changes or SQL connections.'
    }
    elseif ($pool) {
        Write-Ok "Start pool verified: $Part1SqlServerName/$ElasticPoolName. Database membership and the app are unchanged."
    }
    else {
        Write-Host 'Pool creation was not approved; no changes made.'
    }
}
catch {
    $message = $_.Exception.Message -replace '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '[redacted]'
    throw $message
}
