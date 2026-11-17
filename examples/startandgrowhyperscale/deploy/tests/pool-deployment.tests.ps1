$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '..\04-deploy-sql.ps1'
$fixture = [pscustomobject]@{
    Exists = $false; Capacity = 8; Maximum = 8; WrongCreatedMaximum = $false
    Creates = [System.Collections.Generic.List[object]]::new()
    Updates = 0
}
$passed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function az {
    $arguments = @($args)
    $global:LASTEXITCODE = 0
    switch ($arguments[0..2] -join ' ') {
        'account set --subscription' { return }
        'group exists --name' { return 'true' }
        'sql server show' { return '{"location":"eastus2","name":"sql-caldova-network-test"}' }
        'sql server firewall-rule' { return '{}' }
        'sql db show' { return '{"status":"Online"}' }
        'sql elastic-pool create' {
            $fixture.Creates.Add($arguments)
            $fixture.Exists = $true
            $fixture.Capacity = [int]$arguments[[Array]::IndexOf($arguments, '--capacity') + 1]
            $fixture.Maximum = if ($fixture.WrongCreatedMaximum) { 12 } else {
                [int]$arguments[[Array]::IndexOf($arguments, '--db-max-capacity') + 1]
            }
            return '{}'
        }
        'sql elastic-pool update' { $fixture.Updates++; throw 'Existing pools must not be changed implicitly.' }
        'sql elastic-pool show' {
            if (-not $fixture.Exists) { return }
            return (@{
                sku = @{ capacity = $fixture.Capacity }
                perDatabaseSettings = @{ minCapacity = 0; maxCapacity = $fixture.Maximum }
            } | ConvertTo-Json -Compress)
        }
        default { throw "Unexpected Azure command: $($arguments -join ' ')" }
    }
}

$overrides = @{
    AZURE_SUBSCRIPTION_ID = '00000000-0000-0000-0000-000000000000'
    CALDOVA_NETWORK_SQL_SERVER = 'sql-caldova-network-test'
    CALDOVA_NETWORK_SQL_LOCATION = 'eastus2'
}
$previous = @{}
try {
    foreach ($key in $overrides.Keys) {
        $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $overrides[$key], 'Process')
    }
    & $scriptPath -ClientIp '127.0.0.1' | Out-Null
    Assert-True ($fixture.Creates.Count -eq 1) 'A missing pool is created once'
    $passed++
    $create = $fixture.Creates[0]
    Assert-True ($create[[Array]::IndexOf($create, '--db-min-capacity') + 1] -eq '0' -and
        $create[[Array]::IndexOf($create, '--db-max-capacity') + 1] -eq '8') 'An eight-core pool is explicitly capped at eight, not twelve'
    $passed++
    & $scriptPath -ClientIp '127.0.0.1' | Out-Null
    Assert-True ($fixture.Creates.Count -eq 1 -and $fixture.Updates -eq 0) 'A compatible existing eight-core pool is preserved'
    $passed++
    $fixture.Capacity = 24
    $fixture.Maximum = 12
    & $scriptPath -ClientIp '127.0.0.1' | Out-Null
    Assert-True ($fixture.Creates.Count -eq 1 -and $fixture.Updates -eq 0) 'A compatible existing 24-core pool with cap twelve is preserved'
    $passed++
    foreach ($maximum in @(8, 24)) {
        $fixture.Maximum = $maximum
        $failed = $false
        try { & $scriptPath -ClientIp '127.0.0.1' | Out-Null }
        catch { if ($_.Exception.Message -notlike '*approve a separate limit change*') { throw }; $failed = $true }
        Assert-True ($failed -and $fixture.Creates.Count -eq 1 -and $fixture.Updates -eq 0) 'A mismatched existing cap fails without changing or recreating the pool'
        $passed++
    }
    $fixture.Exists = $false
    $fixture.WrongCreatedMaximum = $true
    $failed = $false
    try { & $scriptPath -ClientIp '127.0.0.1' | Out-Null }
    catch { if ($_.Exception.Message -notlike '*approve a separate limit change*') { throw }; $failed = $true }
    Assert-True $failed 'Creation success is not sufficient without independently verified caps'
    $passed++
    Write-Host "PASS: $passed mocked pool deployment checks (no Azure or SQL access)."
}
finally {
    foreach ($key in $previous.Keys) {
        [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process')
    }
}
