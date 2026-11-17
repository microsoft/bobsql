[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\00-config.ps1"

$database = Invoke-AzJson @('sql', 'db', 'show', '--subscription', $ExpectedSubscriptionId,
    '--resource-group', $ResourceGroup, '--server', $SqlServerName, '--name', $DatabaseName,
    '--output', 'json')
if ($database.status -ne 'Online') { throw "Database status is $($database.status)." }
if ($database.currentServiceObjectiveName -ne $DatabaseServiceObjective) {
    throw "Expected $DatabaseServiceObjective; found $($database.currentServiceObjectiveName)."
}
Write-Ok "$($database.currentServiceObjectiveName), $($database.status), minimum capacity $($database.minCapacity)"
Write-Ok "Persisted auto-pause delay: $($database.autoPauseDelay)"

$python = Get-PythonCommand
$verifyScript = Join-Path $PSScriptRoot '..\database\verify_database.py'
& $python $verifyScript `
    --subscription $ExpectedSubscriptionId `
    --server "$SqlServerName.database.windows.net" `
    --database $DatabaseName
if ($LASTEXITCODE -ne 0) { throw "SQL verification failed with exit code $LASTEXITCODE." }

Write-Host "`nStage 1 SQL contract verified." -ForegroundColor Green