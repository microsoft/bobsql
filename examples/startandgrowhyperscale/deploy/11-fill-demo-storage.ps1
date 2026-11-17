[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"

try {
    $account = Invoke-Az @('account', 'show', '--query', '{name:name,id:id}', '--output', 'json')
    if ($account.id -ne $SubscriptionId) { throw 'Configured subscription differs from the current Azure CLI subscription. No changes made.' }
    if ($SqlServerName -notlike 'sql-caldova-network-*' -or $CaldovaDatabase -ne 'caldova-scheduling') {
        throw 'Storage seeding is restricted to the Grow network server and its three named databases.'
    }
    $pool = Invoke-Az @('sql', 'elastic-pool', 'show', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroup, '--server', $SqlServerName, '--name', $ElasticPoolName, '--output', 'json')
    $names = @('caldova-scheduling', 'northbrook-scheduling', 'ridgeview-scheduling')
    foreach ($name in $names) {
        $database = Invoke-Az @('sql', 'db', 'show', '--subscription', $SubscriptionId,
            '--resource-group', $ResourceGroup, '--server', $SqlServerName, '--name', $name, '--output', 'json')
        if ($database.status -ne 'Online' -or $database.elasticPoolId -ne $pool.id) {
            throw "$name must be Online in the existing $ElasticPoolName before storage seeding."
        }
    }
    Write-Host "Subscription: $($account.name); resource group: $ResourceGroup; server: $SqlServerName"
    Write-Host 'Create/verify only demo.StoragePayload, demo.StorageSize and demo.FillStorageBatch.'
    Write-Host 'Fill measured used data: Caldova 18 GiB; Northbrook 12 GiB; Ridgeview 15 GiB.'
    Write-Host 'Grant the existing app user SELECT on the size view and EXECUTE on the bounded batch procedure only.'
    Write-Host 'Existing data is never deleted. Completed batches remain on cancellation; reruns measure and fill only what remains.'
    if (-not $PSCmdlet.ShouldProcess("$SqlServerName : $($names -join ', ')", 'Seed 18/12/15 GiB used synthetic data')) { return }

    dotnet build $AppProject --configuration Release
    if ($LASTEXITCODE -ne 0) { throw 'Build failed; no storage operation started. Stop the local app if it locks build output.' }
    $values = @{
        'StorageFill__Approved' = 'true'
        'Demo__Playback' = 'false'
        'Azure__AppName' = $AppName
        'ConnectionStrings__Scheduling' = "Server=tcp:$SqlServerFqdn,1433;Initial Catalog=caldova-scheduling;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connect Timeout=30"
        'ServerlessMonitor__ResourceId' = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Sql/servers/$SqlServerName/databases/caldova-scheduling"
    }
    $previous = @{}
    foreach ($key in $values.Keys) {
        $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $values[$key], 'Process')
    }
    try {
        dotnet run --project $AppProject --configuration Release --no-build --no-launch-profile -- --fill-demo-storage
        if ($LASTEXITCODE -ne 0) { throw 'Storage fill failed or was interrupted. Partial committed payload data may remain; inspect current sizes before rerunning.' }
    }
    finally {
        foreach ($key in $values.Keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process') }
    }
}
catch { throw ($_.Exception.Message -replace '[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', '[redacted]') }
