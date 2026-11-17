$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '..\14-create-part1-pool.ps1'
$subscription = '00000000-0000-0000-0000-000000000000'
$group = 'caldova-test-rg'
$start = 'sql-caldova-start-test'
$network = 'sql-caldova-network-test'
$serverId = "/subscriptions/$subscription/resourceGroups/$group/providers/Microsoft.Sql/servers/$start"
$poolId = "$serverId/elasticPools/caldova-network-pool"
$passed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    $script:passed++
}

function Reset-Fixture {
    $script:fixture = @{
        Account = @{ id = $subscription; name = 'Test subscription'; state = 'Enabled' }
        User = @{ id = '11111111-1111-1111-1111-111111111111' }
        Server = @{ id = $serverId; location = 'eastus2'; state = 'Ready'; minimalTlsVersion = '1.2'; publicNetworkAccess = 'Enabled' }
        Auth = $true; Firewall = $true; Exists = $false; FailCommand = ''; WrongCreatedMaximum = $false
        Pool = @{
            id = $poolId; name = 'caldova-network-pool'; location = 'eastus2'; state = 'Ready'
            sku = @{ tier = 'Hyperscale'; family = 'Gen5'; capacity = 8 }
            perDatabaseSettings = @{ minCapacity = 0; maxCapacity = 8 }; zoneRedundant = $false
        }
        Databases = @('caldova-scheduling', 'northbrook-scheduling', 'ridgeview-scheduling') | ForEach-Object {
            @{ name = $_; id = "$serverId/databases/$_"; status = 'Online'; sku = @{ tier = 'Hyperscale' }
                requestedBackupStorageRedundancy = 'Local'; zoneRedundant = $false; elasticPoolId = $null }
        }
        Creates = [System.Collections.Generic.List[object]]::new()
    }
}

function az {
    $arguments = @($args)
    $global:LASTEXITCODE = 0
    function Value([string]$Name) {
        $index = [Array]::IndexOf($arguments, $Name)
        if ($index -lt 0 -or $index + 1 -ge $arguments.Count) { throw "Missing $Name" }
        return $arguments[$index + 1]
    }
    $command = if ($arguments[0] -eq 'account') { 'account show' }
        elseif ($arguments[0] -eq 'ad') { 'ad signed-in-user show' }
        elseif ($arguments[2] -in @('ad-only-auth', 'firewall-rule')) { $arguments[0..3] -join ' ' }
        else { $arguments[0..2] -join ' ' }
    if ($arguments[0] -eq 'sql') {
        if ((Value '--subscription') -ne $subscription -or (Value '--resource-group') -ne $group) {
            throw 'Unexpected resource target'
        }
        $serverArgument = if ($arguments -contains '--server') { '--server' } else { '--name' }
        if ((Value $serverArgument) -ne $start) { throw 'Never target Grow' }
    }
    if ($arguments -contains '--no-wait') { throw 'Creation must wait for completion' }
    if ($command -eq $fixture.FailCommand) {
        $global:LASTEXITCODE = 1
        return "Authorization denied for $serverId"
    }
    switch ($command) {
        'account show' { return ($fixture.Account | ConvertTo-Json -Compress) }
        'ad signed-in-user show' { return ($fixture.User | ConvertTo-Json -Compress) }
        'sql server show' { return ($fixture.Server | ConvertTo-Json -Compress) }
        'sql server ad-only-auth get' { return (@{ azureAdOnlyAuthentication = $fixture.Auth } | ConvertTo-Json -Compress) }
        'sql server firewall-rule list' {
            $rules = if ($fixture.Firewall) { @(@{ startIpAddress = '0.0.0.0'; endIpAddress = '0.0.0.0' }) } else { @() }
            return (ConvertTo-Json -InputObject $rules -Compress)
        }
        'sql db list' { return (ConvertTo-Json -InputObject @($fixture.Databases) -Depth 5 -Compress) }
        'sql elastic-pool list' {
            $pools = if ($fixture.Exists) { @($fixture.Pool) } else { @() }
            return (ConvertTo-Json -InputObject $pools -Depth 5 -Compress)
        }
        'sql elastic-pool create' {
            if ((Value '--name') -ne 'caldova-network-pool' -or (Value '--edition') -ne 'Hyperscale' -or
                (Value '--family') -ne 'Gen5' -or (Value '--capacity') -ne '8' -or
                (Value '--db-min-capacity') -ne '0' -or (Value '--db-max-capacity') -ne '8' -or
                (Value '--zone-redundant') -ne 'false') { throw 'Unexpected pool creation settings' }
            $fixture.Creates.Add($arguments)
            $fixture.Exists = $true
            if ($fixture.WrongCreatedMaximum) { $fixture.Pool.perDatabaseSettings.maxCapacity = 12 }
            return '{}'
        }
        'sql elastic-pool show' { return ($fixture.Pool | ConvertTo-Json -Depth 5 -Compress) }
        default { throw "Forbidden/unexpected Azure command: $command" }
    }
}

function Assert-Failure {
    param([scriptblock]$Action, [string]$Pattern)
    $message = $null
    try { & $Action | Out-Null }
    catch { $message = $_.Exception.Message }
    Assert-True ($null -ne $message -and $message -like $Pattern) "Expected failure '$Pattern', got '$message'"
    Assert-True ($message -notmatch [regex]::Escape($subscription)) 'Failure output redacts subscription identifiers'
}

$overrides = @{
    AZURE_SUBSCRIPTION_ID = $subscription; CALDOVA_NETWORK_RESOURCE_GROUP = $group
    CALDOVA_NETWORK_SQL_SERVER = $network; CALDOVA_PART1_SQL_SERVER = $start; CALDOVA_NETWORK_SQL_LOCATION = 'eastus2'
}
$previous = @{}
try {
    foreach ($key in $overrides.Keys) {
        $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $overrides[$key], 'Process')
    }
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-True ($errors.Count -eq 0) 'Pool-only script parses'

    Reset-Fixture
    $output = & $scriptPath -ExpectedServerName $start -WhatIf 6>&1 | Out-String
    Assert-True ($fixture.Creates.Count -eq 0) 'Preview performs no mutation'
    Assert-True ($output -match 'Test subscription' -and $output -notmatch [regex]::Escape($subscription) -and
        $output -notmatch [regex]::Escape($fixture.User.id)) 'Preview uses subscription display name and hides identity IDs'
    & $scriptPath -ExpectedServerName $start -Confirm:$false | Out-Null
    Assert-True ($fixture.Creates.Count -eq 1) 'Creates only the missing Start pool with exact settings'
    & $scriptPath -ExpectedServerName $start -Confirm:$false | Out-Null
    Assert-True ($fixture.Creates.Count -eq 1) 'Compatible existing pool is reused without a write'

    Reset-Fixture
    & $scriptPath -ExpectedServerName $start -Confirm:$false -WhatIf:$false -ErrorAction Stop | Out-Null
    Assert-True ($fixture.Databases.Count -eq 3 -and -not ($fixture.Databases | Where-Object elasticPoolId)) 'Creation leaves all three databases standalone'
    Reset-Fixture
    $fixture.Databases[0].status = 'Paused'
    & $scriptPath -ExpectedServerName $start -WhatIf | Out-Null
    Assert-True ($fixture.Creates.Count -eq 0) 'A paused Caldova database is inspected through ARM only'

    Reset-Fixture
    Assert-Failure { & $scriptPath -ExpectedServerName $network -WhatIf } '*expected server*'
    foreach ($change in @(
        { $fixture.Account.id = '22222222-2222-2222-2222-222222222222' },
        { $fixture.Account.state = 'Disabled' },
        { $fixture.User.id = $null },
        { $fixture.Server.id = $serverId.Replace($start, $network) },
        { $fixture.Server.location = 'westus' },
        { $fixture.Server.state = 'Creating' },
        { $fixture.Server.minimalTlsVersion = '1.0' },
        { $fixture.Server.publicNetworkAccess = 'Disabled' },
        { $fixture.Auth = $false },
        { $fixture.Firewall = $false },
        { $fixture.Databases = @($fixture.Databases | Where-Object name -ne 'ridgeview-scheduling') },
        { $fixture.Databases[2].zoneRedundant = $true },
        { $fixture.Databases[2].requestedBackupStorageRedundancy = 'Geo' },
        { $fixture.Databases[2].elasticPoolId = "$serverId/elasticPools/other" }
    )) {
        Reset-Fixture
        & $change
        Assert-Failure { & $scriptPath -ExpectedServerName $start -Confirm:$false } '*'
        Assert-True ($fixture.Creates.Count -eq 0) 'Incompatible preflight stops before creation'
    }
    foreach ($change in @(
        { $fixture.Pool.id = $poolId.Replace($start, $network) },
        { $fixture.Pool.state = 'Creating' },
        { $fixture.Pool.sku.tier = 'GeneralPurpose' },
        { $fixture.Pool.sku.family = 'Gen4' },
        { $fixture.Pool.sku.capacity = 24 },
        { $fixture.Pool.perDatabaseSettings.minCapacity = 1 },
        { $fixture.Pool.perDatabaseSettings.minCapacity = $null },
        { $fixture.Pool.perDatabaseSettings.maxCapacity = 12 },
        { $fixture.Pool.zoneRedundant = $true }
    )) {
        Reset-Fixture
        $fixture.Exists = $true
        & $change
        Assert-Failure { & $scriptPath -ExpectedServerName $start -WhatIf } '*pool does not match*'
        Assert-True ($fixture.Creates.Count -eq 0) 'Mismatched existing pool is not recreated or changed'
    }
    foreach ($command in @('sql server show', 'sql server ad-only-auth get', 'sql server firewall-rule list',
        'sql db list', 'sql elastic-pool list', 'sql elastic-pool create', 'sql elastic-pool show')) {
        Reset-Fixture
        $fixture.FailCommand = $command
        Assert-Failure { & $scriptPath -ExpectedServerName $start -Confirm:$false } '*Authorization denied*'
        Assert-True ($fixture.Creates.Count -le 1) 'Authorization or partial creation failures are not retried'
    }
    Reset-Fixture
    $fixture.WrongCreatedMaximum = $true
    Assert-Failure { & $scriptPath -ExpectedServerName $start -Confirm:$false } '*pool does not match*'
    Assert-True ($fixture.Creates.Count -eq 1) 'Creation response alone is not proof; independent verification rejects wrong caps'
    Write-Host "PASS: $passed mocked Start pool-only checks (no Azure or SQL access)."
}
finally {
    foreach ($key in $previous.Keys) {
        [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process')
    }
}
