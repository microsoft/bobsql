[CmdletBinding()]
param(
    [string]$ServerInstance = 'localhost'
)

$ErrorActionPreference = 'Stop'
$sqlcmd = Get-Command sqlcmd -ErrorAction Stop
$testScript = Join-Path $PSScriptRoot 'test-history-rag.sql'
Write-Host "Testing optional historical RAG on '$ServerInstance'..." -ForegroundColor Cyan
Write-Host 'This verifies source validation and three live persisted briefings: explicit history, integrated top-three retrieval, and current facts only.'
& $sqlcmd.Source -S $ServerInstance -d CaldovaRegionalCare -E -C -b -l 30 -t 0 -w 500 -i $testScript
if ($LASTEXITCODE -ne 0) {
    throw "Historical RAG tests failed (sqlcmd exit code $LASTEXITCODE). Review the SQL error above."
}
Write-Host 'Optional historical RAG tests passed.' -ForegroundColor Green
