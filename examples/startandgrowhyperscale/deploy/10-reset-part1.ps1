[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$ExpectedServerName
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"

if ($ExpectedServerName -ne $Part1SqlServerName -or $Part1SqlServerName -eq $SqlServerName -or
    $Part1SqlServerName -notlike 'sql-caldova-start-*') {
    throw 'Reset is restricted to the explicitly confirmed, separate sql-caldova-start-* server.'
}

$serverId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Sql/servers/$Part1SqlServerName"
$databaseId = "$serverId/databases/$CaldovaDatabase"

Write-Step 'Scene 2 reset plan'
[pscustomobject]@{
    Subscription = $SubscriptionId
    DeleteOnly = $databaseId
    DataLoss = 'All schema, data, and bookings in this Start database will be deleted'
    Keep = 'Resource group, both logical servers, all Grow databases, pool, and app'
    AfterRedeployment = 'Use the off-camera population prompt to recreate schema and synthetic data'
} | Format-List | Out-String | Write-Host

$groupExists = Invoke-Az @('group', 'exists', '--subscription', $SubscriptionId,
    '--name', $ResourceGroup, '--output', 'tsv') -Raw
if ($groupExists -notin @('true', 'false')) { throw 'Unexpected resource-group existence response.' }
if ($groupExists -eq 'false') {
    Write-Skip 'Resource group is absent; the Start database is already absent.'
    return
}
$servers = @(Invoke-Az @('sql', 'server', 'list', '--subscription', $SubscriptionId,
    '--resource-group', $ResourceGroup, '--output', 'json'))
$server = $servers | Where-Object { $_.name -eq $Part1SqlServerName }
if (-not $server) {
    Write-Skip 'Start server is absent; the Start database is already absent.'
    return
}
if ($server.id -ne $serverId) { throw 'Start server identity does not match the reset target.' }

$databases = @(Invoke-Az @('sql', 'db', 'list', '--subscription', $SubscriptionId,
    '--resource-group', $ResourceGroup, '--server', $Part1SqlServerName, '--output', 'json'))
$database = $databases | Where-Object { $_.name -eq $CaldovaDatabase }
if (-not $database) {
    Write-Skip 'Start database is already absent. No changes made.'
    return
}
if ($database.id -ne $databaseId) { throw 'Database identity does not match the reset target.' }
if ($database.status -notin @('Online', 'Paused')) {
    throw "Start database is $($database.status); wait for its current operation to complete."
}

if ($PSCmdlet.ShouldProcess($databaseId, 'Delete only the Start database and its contents')) {
    Invoke-Az @('sql', 'db', 'delete', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroup, '--server', $Part1SqlServerName,
        '--name', $CaldovaDatabase, '--yes', '--output', 'none') | Out-Null
    $remaining = @(Invoke-Az @('sql', 'db', 'list', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroup, '--server', $Part1SqlServerName, '--output', 'json'))
    if ($remaining | Where-Object { $_.name -eq $CaldovaDatabase }) {
        throw 'Reset verification failed: the Start database still exists.'
    }
    Write-Ok 'Start database deletion verified. Redeploy in Scene 2, then populate off camera.'
}
