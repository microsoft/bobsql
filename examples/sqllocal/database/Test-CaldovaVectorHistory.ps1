[CmdletBinding()]
param(
    [string]$ServerInstance = 'localhost'
)

$ErrorActionPreference = 'Stop'
$sqlcmd = Get-Command sqlcmd -ErrorAction Stop
$testScript = Join-Path $PSScriptRoot 'test-vector-history.sql'
if (-not (Test-Path -LiteralPath $testScript -PathType Leaf)) {
    throw "Vector verification script was not found at '$testScript'."
}

Write-Host "Testing CaldovaRegionalCare vector history on '$ServerInstance'..." -ForegroundColor Cyan
Write-Host 'Tests native embedding regeneration, vector-index rebuilding, repeat-safe refresh, semantic ranking, patient isolation, and invalid-input/stale-vector/missing-index rejection.'
Write-Host 'Requires the optional vector schema, synthetic history seed, and encrypted Nemotron credential to be configured already.'

$timer = [Diagnostics.Stopwatch]::StartNew()
& $sqlcmd.Source -S $ServerInstance -d CaldovaRegionalCare -E -C -b -l 30 -t 0 -w 500 -i $testScript
if ($LASTEXITCODE -ne 0) {
    throw "Caldova vector history tests failed (sqlcmd exit code $LASTEXITCODE). Review the SQL error above."
}
$timer.Stop()
Write-Host ('Caldova vector history tests passed in {0:N1} seconds.' -f $timer.Elapsed.TotalSeconds) -ForegroundColor Green
