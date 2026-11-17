[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$ExpectedServerName,
    [switch]$IncludeGrowth
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"
$previous = @{}
try {
    $account = Invoke-Az @('account', 'show', '--query', '{name:name,id:id}', '--output', 'json')
    if ($account.id -ne $SubscriptionId -or $ExpectedServerName -ne $SqlServerName -or
        $SqlServerName -notlike 'sql-caldova-network-*') {
        throw 'Rehearsal target does not match the current CLI subscription and expected Grow server.'
    }
    $pool = Invoke-Az @('sql', 'elastic-pool', 'show', '-g', $ResourceGroup,
        '-s', $SqlServerName, '-n', $ElasticPoolName, '--query',
        '{state:state,tier:sku.tier,capacity:sku.capacity,min:perDatabaseSettings.minCapacity,max:perDatabaseSettings.maxCapacity}',
        '--output', 'json')
    if ($pool.state -ne 'Ready' -or $pool.tier -ne 'Hyperscale' -or
        $pool.capacity -notin @(8, 24) -or $pool.min -ne 0 -or $pool.max -ne 8) {
        throw 'The existing Ready Hyperscale pool must retain supported capacity and 0-8 per-database limits.'
    }
    Write-Host "Target: $($account.name); $ResourceGroup; $SqlServerName; $ElasticPoolName"
    Write-Host 'Run real bounded scheduling/CPU work on Caldova, Northbrook, and Ridgeview; capture actual SQL CPU samples.'
    if ($IncludeGrowth) { Write-Host 'Also insert bounded Caldova synthetic payload until real used/allocated space crosses 20 GiB, capped at 21 GiB used.' }
    Write-Host 'No booking, schema setup, reset, database move, pool scaling, server, or preview-setting changes.'
    if (-not $PSCmdlet.ShouldProcess("$SqlServerName : $ElasticPoolName",
        "Run real SQL workload; synthetic Caldova growth: $([bool]$IncludeGrowth)")) { return }
    $exe = Join-Path $PSScriptRoot '..\app\bin\Release\net10.0\CaldovaNetworkScheduling.exe'
    if (-not (Test-Path -LiteralPath $exe)) { throw 'Build the app in Release before running the real rehearsal.' }
    $settings = @{
        'PoolRehearsal__Approved' = 'true'
        'PoolScaling__Enabled' = 'true'
        'PoolGrowth__Enabled' = ([bool]$IncludeGrowth).ToString()
        'PoolPresentation__Enabled' = 'false'
        'Demo__Playback' = 'false'
        'ServerlessMonitor__ResourceId' = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Sql/servers/$SqlServerName/databases/$CaldovaDatabase"
        'ConnectionStrings__Scheduling' = "Server=tcp:$SqlServerFqdn,1433;Initial Catalog=$CaldovaDatabase;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connect Timeout=30"
    }
    foreach ($name in $settings.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $settings[$name], 'Process')
    }
    & $exe --rehearse-pool
    if ($LASTEXITCODE -ne 0) { throw "Real pool rehearsal failed with exit code $LASTEXITCODE; inspect committed state before another run." }
}
catch { throw ($_.Exception.Message -replace '(?i)[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', '[redacted-id]') }
finally {
    foreach ($name in $previous.Keys) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') }
}
