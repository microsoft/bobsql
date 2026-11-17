[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Pooled', 'Standalone')]
    [string]$Mode,
    [ValidateSet('Grow', 'Start')][string]$Target = 'Grow',
    [string]$ExpectedServerName,
    [ValidateRange(1, 3600)][int]$WaitTimeoutSeconds = 1800,
    [ValidateRange(1, 60)][int]$PollIntervalSeconds = 5
)

$ErrorActionPreference = 'Stop'
trap {
    throw ($_.Exception.Message -replace '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '[redacted]')
}
. "$PSScriptRoot\00-config.ps1"
$membershipServer = if ($Target -eq 'Start') { $Part1SqlServerName } else { $SqlServerName }
$membershipFqdn = "$membershipServer.database.windows.net"
if ($Target -eq 'Start' -and ($ExpectedServerName -ne $Part1SqlServerName -or
    $Part1SqlServerName -eq $SqlServerName -or $Part1SqlServerName -notlike 'sql-caldova-start-*')) {
    throw 'Start membership requires the explicit expected Start server, separate from Grow.'
}
if ($ExpectedServerName -and $ExpectedServerName -ne $membershipServer) {
    throw 'The expected server does not match the membership target.'
}
$account = Invoke-Az @('account', 'show', '--output', 'json')
if ($account.id -ne $SubscriptionId -or $account.state -ne 'Enabled') {
    throw 'The current Azure CLI subscription does not match the configured target. No subscription was switched.'
}

function Get-DemoDatabase {
    param([string]$Name)
    Invoke-Az @('sql', 'db', 'show', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroup, '--server', $membershipServer, '--name', $Name, '--output', 'json')
}

function Wait-DemoDatabase {
    param([string]$Name, [scriptblock]$Ready, [string]$Failure)
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($WaitTimeoutSeconds)
    do {
        $database = Get-DemoDatabase $Name
        if ($database.id -ne "$membershipServerId/databases/$Name" -or -not $database.status) {
            throw "Invalid ARM identity/status response while observing $Name. No update was retried."
        }
        if (& $Ready $database) { return $database }
        if ($database.status -in @('Failed', 'Inaccessible', 'Suspect', 'Offline')) {
            throw "$Name is $($database.status). $Failure"
        }
        if ([DateTimeOffset]::UtcNow -ge $deadline) { throw "Timed out waiting for $Name. $Failure" }
        Start-Sleep -Seconds $PollIntervalSeconds
    } while ($true)
}

function Test-DesiredState {
    param($Database, $Target)
    if ($Database.id -ne "$membershipServerId/databases/$($Target.Name)" -or $Database.sku.tier -ne 'Hyperscale') {
        return $false
    }
    if ($Mode -eq 'Pooled') {
        return ($Database.elasticPoolId -eq $pool.id -and $Database.status -eq 'Online')
    }

    if ($Database.elasticPoolId -or $Database.currentServiceObjectiveName -ne $Target.Objective) { return $false }
    if ($Database.status -notin @('Online', 'Paused')) { return $false }
    if ($Target.Name -eq $CaldovaDatabase) {
        return ($Database.minCapacity -eq $CaldovaMinVCores -and
            $Database.autoPauseDelay -eq $AutoPauseDelayMinutes)
    }
    return $true
}

function Set-DemoDatabase {
    param([string]$Name, [string[]]$ComputeArguments)
    Invoke-Az (@('sql', 'db', 'update', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroup, '--server', $membershipServer, '--name', $Name) +
        $ComputeArguments + @('--output', 'json')) | Out-Null
}

$targets = @(
    [pscustomobject]@{ Name = $CaldovaDatabase; Objective = "HS_S_Gen5_$CaldovaMaxVCores" }
    foreach ($acquired in $AcquiredDatabases) {
        [pscustomobject]@{ Name = $acquired.Name; Objective = "HS_Gen5_$($acquired.VCores)" }
    }
)

Write-Step "Preflight: $Mode on $membershipFqdn (resource group $ResourceGroup)"
$pool = Invoke-Az @('sql', 'elastic-pool', 'show', '--subscription', $SubscriptionId,
    '--resource-group', $ResourceGroup, '--server', $membershipServer, '--name', $ElasticPoolName, '--output', 'json')
$membershipServerId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Sql/servers/$membershipServer"
$expectedPoolId = "$membershipServerId/elasticPools/$ElasticPoolName"
if ($pool.id -ne $expectedPoolId -or $pool.sku.tier -ne 'Hyperscale' -or $pool.sku.family -ne 'Gen5' -or $pool.state -ne 'Ready') {
    throw "Expected the existing, Ready Hyperscale pool $expectedPoolId; received id '$($pool.id)', tier '$($pool.sku.tier)', state '$($pool.state)'. No databases were changed."
}

$databases = @{}
foreach ($databaseTarget in $targets) {
    $database = Get-DemoDatabase $databaseTarget.Name
    $expectedDatabaseId = "$membershipServerId/databases/$($databaseTarget.Name)"
    # ARM reports pooled databases as sku 'ElasticPool' with no family; they inherit the pool's Gen5.
    $family = if ($database.elasticPoolId -eq $pool.id) { $pool.sku.family } else { $database.sku.family }
    if ($database.id -ne $expectedDatabaseId -or $database.sku.tier -ne 'Hyperscale' -or $family -ne 'Gen5') {
        throw "Expected Hyperscale Gen5 database $expectedDatabaseId. No databases were changed."
    }
    if ($database.elasticPoolId -and $database.elasticPoolId -ne $pool.id) {
        throw "$($databaseTarget.Name) belongs to another pool. Refusing to move it. No databases were changed."
    }
    if ($database.status -notin @('Online', 'Paused')) {
        if ($WhatIfPreference) {
            throw "$($databaseTarget.Name) is $($database.status); wait for its current operation to finish. No databases were changed."
        }
        Write-Host "$($databaseTarget.Name): waiting for the existing Azure operation using ARM reads only."
        $database = Wait-DemoDatabase $databaseTarget.Name { param($db) $db.status -in @('Online', 'Paused') } `
            'The existing operation did not settle. No new database updates were submitted.'
        # Recheck identity and placement after an interrupted operation settles.
        $family = if ($database.elasticPoolId -eq $pool.id) { $pool.sku.family } else { $database.sku.family }
        if ($database.id -ne $expectedDatabaseId -or $database.sku.tier -ne 'Hyperscale' -or $family -ne 'Gen5' -or
            ($database.elasticPoolId -and $database.elasticPoolId -ne $pool.id)) {
            throw "$($databaseTarget.Name) settled in an unexpected configuration. No databases were changed."
        }
    }
    if ($Mode -eq 'Pooled' -and
        ($database.zoneRedundant -ne $pool.zoneRedundant -or
        $database.requestedBackupStorageRedundancy -ne $BackupStorageRedundancy)) {
        throw "$($databaseTarget.Name) must match pool zone redundancy and demo backup redundancy ($BackupStorageRedundancy). No databases were changed."
    }
    $databases[$databaseTarget.Name] = $database
}

Write-Host 'Stop appointment traffic before moving databases. Connections can be interrupted.'
Write-Host 'Moves are sequential, not atomic. After failure or interruption, inspect all three databases before continuing the same approved target/direction.'
if ($Mode -eq 'Standalone') {
    Write-Host 'Native cross-database queries will no longer work. Caldova returns to serverless; the empty pool is retained.'
}

$remaining = @($targets | Where-Object { -not (Test-DesiredState $databases[$_.Name] $_) })
if ($remaining.Count -gt 0) {
    $plan = ($remaining | ForEach-Object {
        if ($Mode -eq 'Pooled') { "$($_.Name) -> $ElasticPoolName (serverless conversion if needed)" }
        else {
            "$($_.Name) -> $($_.Objective)" +
                $(if ($_.Name -eq $CaldovaDatabase) { " (min $CaldovaMinVCores, auto-pause $AutoPauseDelayMinutes min)" })
        }
    }) -join '; '
    if (-not $PSCmdlet.ShouldProcess($membershipFqdn, "Apply $Mode to all remaining databases: $plan")) {
        Write-Host 'Plan only: no membership updates were applied. No overall success is claimed.'
        return
    }
}
foreach ($databaseTarget in $targets) {
    $database = Get-DemoDatabase $databaseTarget.Name
    if (Test-DesiredState $database $databaseTarget) {
        Write-Skip "$($databaseTarget.Name) already matches $Mode"
        continue
    }

    $action = if ($Mode -eq 'Pooled') {
        "Move into $ElasticPoolName (convert serverless to provisioned first if needed)"
    }
    else {
        "Remove from pool and restore $($databaseTarget.Objective)" +
        $(if ($databaseTarget.Name -eq $CaldovaDatabase) { " (min $CaldovaMinVCores, auto-pause $AutoPauseDelayMinutes min)" })
    }
    Write-Step "$($databaseTarget.Name): $action"
    try {
        $family = if ($database.elasticPoolId -eq $pool.id) { $pool.sku.family } else { $database.sku.family }
        if ($database.id -ne "$membershipServerId/databases/$($databaseTarget.Name)" -or
            $database.sku.tier -ne 'Hyperscale' -or $family -ne 'Gen5' -or
            ($database.elasticPoolId -and $database.elasticPoolId -ne $pool.id) -or
            $database.status -notin @('Online', 'Paused') -or ($Mode -eq 'Pooled' -and
                ($database.zoneRedundant -ne $pool.zoneRedundant -or
                $database.requestedBackupStorageRedundancy -ne $BackupStorageRedundancy))) {
            throw 'Database placement or readiness changed after preflight; inspect it before a new submission.'
        }
        if ($Mode -eq 'Pooled') {
            # Pools use provisioned compute; make the serverless conversion explicit.
            if ($database.currentServiceObjectiveName -like 'HS_S_*') {
                Set-DemoDatabase $databaseTarget.Name @('--edition', 'Hyperscale', '--compute-model', 'Provisioned',
                    '--service-objective', "HS_Gen5_$CaldovaMaxVCores")
                $database = Wait-DemoDatabase $databaseTarget.Name { param($db)
                    -not $db.elasticPoolId -and $db.currentServiceObjectiveName -eq "HS_Gen5_$CaldovaMaxVCores" -and
                        $db.status -eq 'Online'
                } 'Serverless-to-provisioned conversion did not reach the expected online standalone state.'
            }
            Set-DemoDatabase $databaseTarget.Name @('--elastic-pool', $pool.id)
        }
        elseif ($databaseTarget.Name -eq $CaldovaDatabase) {
            if ($database.elasticPoolId) {
                # A standalone service objective removes pool membership before enabling serverless.
                Set-DemoDatabase $databaseTarget.Name @('--service-objective', "HS_Gen5_$CaldovaMaxVCores")
                $database = Wait-DemoDatabase $databaseTarget.Name { param($db)
                    -not $db.elasticPoolId -and $db.currentServiceObjectiveName -eq "HS_Gen5_$CaldovaMaxVCores" -and
                        $db.status -eq 'Online'
                } 'Pool removal did not reach the expected online standalone state.'
            }
            Set-DemoDatabase $databaseTarget.Name @('--edition', 'Hyperscale', '--compute-model', 'Serverless',
                '--service-objective', $databaseTarget.Objective, '--min-capacity', "$CaldovaMinVCores",
                '--auto-pause-delay', "$AutoPauseDelayMinutes")
        }
        else {
            Set-DemoDatabase $databaseTarget.Name @('--service-objective', $databaseTarget.Objective)
        }

        Wait-DemoDatabase $databaseTarget.Name { param($db) Test-DesiredState $db $databaseTarget } `
            'Azure returned without the requested final database configuration.' | Out-Null
        Write-Ok "$($databaseTarget.Name) verified"
    }
    catch {
        $failure = $_.Exception.Message
        foreach ($item in $targets) {
            try {
                $current = Get-DemoDatabase $item.Name
                $placement = if ($current.elasticPoolId -eq $pool.id) { $ElasticPoolName }
                    elseif ($current.elasticPoolId) { 'Other pool' } else { 'Standalone' }
                Write-Host "$($item.Name): $($current.status), $($current.currentServiceObjectiveName), $placement"
            }
            catch {
                Write-Host ("$($item.Name): state could not be read: " +
                    ($_.Exception.Message -replace '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '[redacted]'))
            }
        }
        throw "$($databaseTarget.Name) failed while applying $Mode on $membershipServer. Earlier moves may have completed; no updates were retried and no rollback was attempted. Inspect all three placements before continuing the same approved target/direction. Details: $failure"
    }
}

Write-Step 'Verifying all three databases'
$summary = foreach ($databaseTarget in $targets) {
    $database = Get-DemoDatabase $databaseTarget.Name
    if (-not (Test-DesiredState $database $databaseTarget)) {
        throw "$($databaseTarget.Name) no longer matches $Mode on $membershipServer. Inspect all three current placements."
    }
    [pscustomobject]@{
        Database = $database.name
        Status = $database.status
        Objective = $database.currentServiceObjectiveName
        Pool = if ($database.elasticPoolId) { $ElasticPoolName } else { 'None' }
        MinVCores = $database.minCapacity
        AutoPauseMinutes = $database.autoPauseDelay
    }
}
$summary | Format-List | Out-Host
Write-Ok "All three databases verified: $Mode. The pool was retained; no data was deleted."
