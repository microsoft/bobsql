[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$preparePath = Join-Path $PSScriptRoot '..\00-prepare-part1.ps1'
$resetPath = Join-Path $PSScriptRoot '..\10-reset-part1.ps1'
$removePath = Join-Path $PSScriptRoot '..\99-remove.ps1'
$subscription = '00000000-0000-0000-0000-000000000000'
$group = 'caldova-test-rg'
$start = 'sql-caldova-start-test'
$network = 'sql-caldova-network-test'
$serverId = "/subscriptions/$subscription/resourceGroups/$group/providers/Microsoft.Sql/servers/$start"
$databaseId = "$serverId/databases/caldova-scheduling"
$passed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Reset-Fixture {
    $script:fixture = @{
        GroupExists = $true
        ServerExists = $true
        DatabaseExists = $true
        Server = @{
            id = $serverId; name = $start; location = 'eastus2'
            minimalTlsVersion = '1.2'; publicNetworkAccess = 'Enabled'
        }
        Database = @{ id = $databaseId; name = 'caldova-scheduling'; status = 'Online' }
        AdOnly = $true
        User = @{ id = '11111111-1111-1111-1111-111111111111'; userPrincipalName = 'presenter@example.test' }
        FailCommand = ''
        IgnoreDelete = $false
        IgnoreGroupCreate = $false
        IgnoreServerCreate = $false
        Calls = [System.Collections.Generic.List[string]]::new()
        Mutations = [System.Collections.Generic.List[string]]::new()
    }
}

function az {
    $arguments = @($args)
    $global:LASTEXITCODE = 0
    function Get-Argument {
        param([string]$Name)
        $index = [Array]::IndexOf($arguments, $Name)
        Assert-True ($index -ge 0 -and $index + 1 -lt $arguments.Count) "Missing $Name"
        return $arguments[$index + 1]
    }
    Assert-True ($arguments -notcontains '--no-wait') 'Operations must wait for completion'
    if (($arguments[0..2] -join ' ') -eq 'ad signed-in-user show') {
        Assert-True ($arguments -notcontains '--subscription') 'Entra identity lookup must not pass the unsupported subscription option'
        $command = 'ad signed-in-user show'
    }
    else {
        Assert-True ((Get-Argument '--subscription') -eq $subscription) 'Resource calls must pin the expected subscription'
        $command = ($arguments[0..([Array]::IndexOf($arguments, '--subscription') - 1)] -join ' ')
    }
    $fixture.Calls.Add($command)
    if ($arguments -contains '--resource-group') {
        Assert-True ((Get-Argument '--resource-group') -eq $group) 'Unexpected resource group'
    }
    if ($arguments -contains '--server') {
        Assert-True ((Get-Argument '--server') -eq $start) 'Never target Grow SQL'
    }
    if ($command -eq $fixture.FailCommand) {
        $global:LASTEXITCODE = 1
        return 'Simulated Azure authorization/operation failure'
    }
    switch ($command) {
        'group exists' {
            Assert-True ((Get-Argument '--name') -eq $group) 'Unexpected group'
            return $fixture.GroupExists.ToString().ToLowerInvariant()
        }
        'group create' {
            Assert-True ((Get-Argument '--name') -eq $group) 'Unexpected group creation'
            $fixture.Mutations.Add($command)
            if (-not $fixture.IgnoreGroupCreate) { $fixture.GroupExists = $true }
            return '{}'
        }
        'sql server list' {
            $servers = @(@{ name = $network; id = $serverId.Replace($start, $network) })
            if ($fixture.ServerExists) { $servers += $fixture.Server }
            return (ConvertTo-Json -InputObject $servers -Depth 5 -Compress)
        }
        'sql server ad-only-auth get' {
            Assert-True ((Get-Argument '--name') -eq $start) 'Authentication check must target Start'
            return (@{ azureADOnlyAuthentication = $fixture.AdOnly } | ConvertTo-Json -Compress)
        }
        'ad signed-in-user show' { return ($fixture.User | ConvertTo-Json -Compress) }
        'sql server create' {
            Assert-True ((Get-Argument '--name') -eq $start) 'Only create Start server'
            Assert-True ($arguments -contains '--enable-ad-only-auth') 'Entra-only is required'
            Assert-True ((Get-Argument '--minimal-tls-version') -eq '1.2') 'TLS 1.2 required'
            Assert-True ((Get-Argument '--external-admin-sid') -eq $fixture.User.id) 'Use confirmed Entra user'
            $fixture.Mutations.Add($command)
            if (-not $fixture.IgnoreServerCreate) { $fixture.ServerExists = $true }
            return ($fixture.Server | ConvertTo-Json -Compress)
        }
        'sql server show' {
            Assert-True ((Get-Argument '--name') -eq $start) 'Only inspect Start server'
            if (-not $fixture.ServerExists) {
                $global:LASTEXITCODE = 1
                return 'Server not found'
            }
            return ($fixture.Server | ConvertTo-Json -Compress)
        }
        'sql db list' {
            $databases = @(@{ name = 'master' }, @{ name = 'keep-me'; id = "$serverId/databases/keep-me" })
            if ($fixture.DatabaseExists) { $databases += $fixture.Database }
            return (ConvertTo-Json -InputObject $databases -Depth 5 -Compress)
        }
        'sql db delete' {
            Assert-True ((Get-Argument '--name') -eq 'caldova-scheduling') 'Only delete Start scheduling database'
            Assert-True ($arguments -contains '--yes') 'CLI deletion must be noninteractive after ShouldProcess approval'
            $fixture.Mutations.Add($command)
            if (-not $fixture.IgnoreDelete) { $fixture.DatabaseExists = $false }
            return
        }
        default { throw "Unexpected Azure command: $($arguments -join ' ')" }
    }
}

function Assert-Failure {
    param([scriptblock]$Action, [string]$Pattern)
    $message = $null
    try { & $Action | Out-Null }
    catch { $message = $_.ToString() }
    Assert-True ($null -ne $message -and $message -like $Pattern) "Expected '$Pattern', got '$message'"
}

$overrides = @{
    AZURE_SUBSCRIPTION_ID = $subscription
    CALDOVA_NETWORK_RESOURCE_GROUP = $group
    CALDOVA_NETWORK_SQL_SERVER = $network
    CALDOVA_PART1_SQL_SERVER = $start
    CALDOVA_NETWORK_SQL_LOCATION = 'eastus2'
}
$previous = @{}
try {
    foreach ($key in $overrides.Keys) {
        $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $overrides[$key], 'Process')
    }
    foreach ($path in @($preparePath, $resetPath, $removePath)) {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
        Assert-True ($errors.Count -eq 0) "$path must parse"
        $passed++
    }

    Reset-Fixture
    Assert-Failure { & $removePath -Confirm:$false } '*Full teardown is disabled*'
    Assert-Failure { & $removePath -WhatIf } '*Full teardown is disabled*'
    Assert-True ($fixture.Calls.Count -eq 0) 'Full teardown must be blocked before any Azure call'
    $passed += 2

    Reset-Fixture
    & $resetPath -ExpectedServerName $start -WhatIf | Out-Null
    Assert-True ($fixture.Mutations.Count -eq 0 -and $fixture.DatabaseExists) 'Reset preview must not delete'
    $passed++

    foreach ($status in @('Online', 'Paused')) {
        Reset-Fixture
        $fixture.Database.status = $status
        & $resetPath -ExpectedServerName $start -Confirm:$false | Out-Null
        Assert-True (-not $fixture.DatabaseExists -and $fixture.Mutations.Count -eq 1) 'Delete exactly one Start database'
        $passed++
    }
    foreach ($absent in @('GroupExists', 'ServerExists', 'DatabaseExists')) {
        Reset-Fixture
        $fixture[$absent] = $false
        & $resetPath -ExpectedServerName $start -Confirm:$false | Out-Null
        Assert-True ($fixture.Mutations.Count -eq 0) 'Already absent must be a no-op'
        $passed++
    }
    Reset-Fixture
    Assert-Failure { & $resetPath -ExpectedServerName $network -Confirm:$false } '*restricted*'
    Assert-True ($fixture.Calls.Count -eq 0) 'Wrong confirmation must fail before Azure calls'
    $passed++

    $env:CALDOVA_PART1_SQL_SERVER = $network
    Assert-Failure { & $resetPath -ExpectedServerName $network -Confirm:$false } '*restricted*'
    Assert-Failure { & $preparePath } '*separate*'
    $env:CALDOVA_PART1_SQL_SERVER = $start
    $passed += 2

    foreach ($fault in @('ServerId', 'DatabaseId', 'Busy', 'ReadFailure', 'DeleteFailure', 'StillExists')) {
        Reset-Fixture
        $pattern = switch ($fault) {
            'ServerId' { $fixture.Server.id = 'wrong'; '*server identity*' }
            'DatabaseId' { $fixture.Database.id = 'wrong'; '*Database identity*' }
            'Busy' { $fixture.Database.status = 'Scaling'; '*current operation*' }
            'ReadFailure' { $fixture.FailCommand = 'sql db list'; '*Simulated Azure*' }
            'DeleteFailure' { $fixture.FailCommand = 'sql db delete'; '*Simulated Azure*' }
            'StillExists' { $fixture.IgnoreDelete = $true; '*still exists*' }
        }
        Assert-Failure { & $resetPath -ExpectedServerName $start -Confirm:$false } $pattern
        if ($fault -ne 'StillExists') {
            Assert-True ($fixture.Mutations.Count -eq 0) 'Failed preflight/delete must not record a completed mutation'
        }
        $passed++
    }

    Reset-Fixture
    & $preparePath | Out-Null
    Assert-True ($fixture.Mutations.Count -eq 0) 'Existing compatible resources must be reused'
    $passed++
    Reset-Fixture
    $fixture.GroupExists = $false
    $fixture.ServerExists = $false
    & $preparePath -WhatIf | Out-Null
    Assert-True ($fixture.Mutations.Count -eq 0) 'Preparation preview must not create anything'
    $passed++
    & $preparePath | Out-Null
    Assert-True (($fixture.Mutations -join ',') -eq 'group create,sql server create') 'Create group and server only'
    $fixture.Mutations.Clear()
    & $preparePath | Out-Null
    Assert-True ($fixture.Mutations.Count -eq 0) 'Repeated preparation must be a no-op'
    $passed += 2
    Reset-Fixture
    $fixture.ServerExists = $false
    & $preparePath | Out-Null
    Assert-True (($fixture.Mutations -join ',') -eq 'sql server create') 'Keep existing resource group'
    $passed++

    foreach ($fault in @('Region', 'Tls', 'PublicAccess', 'Auth', 'ReadFailure', 'GroupCreate', 'ServerCreate', 'MissingUser')) {
        Reset-Fixture
        $pattern = switch ($fault) {
            'Region' { $fixture.Server.location = 'westus'; '*region*' }
            'Tls' { $fixture.Server.minimalTlsVersion = '1.0'; '*TLS 1.2*' }
            'PublicAccess' { $fixture.Server.publicNetworkAccess = 'Disabled'; '*public endpoint*' }
            'Auth' { $fixture.AdOnly = $false; '*Entra-only*' }
            'ReadFailure' { $fixture.FailCommand = 'sql server list'; '*Simulated Azure*' }
            'GroupCreate' {
                $fixture.GroupExists = $false; $fixture.ServerExists = $false
                $fixture.IgnoreGroupCreate = $true; '*could not be verified*'
            }
            'ServerCreate' {
                $fixture.ServerExists = $false; $fixture.IgnoreServerCreate = $true
                '*Server not found*'
            }
            'MissingUser' {
                $fixture.ServerExists = $false; $fixture.User = @{}
                '*signed-in Entra user*'
            }
        }
        Assert-Failure { & $preparePath } $pattern
        $passed++
    }
    Write-Host "PASS: $passed Part 1 lifecycle tests (mocked Azure CLI; no live changes)." -ForegroundColor Green
}
finally {
    foreach ($key in $previous.Keys) {
        [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process')
    }
}
