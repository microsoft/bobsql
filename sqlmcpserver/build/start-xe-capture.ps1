<#
.SYNOPSIS
    Demo 3 pre-flight — create & start the Extended Events capture session so you can
    watch the SQL MCP Server's parameterized T-SQL live in SSMS (Watch Live Data).

.DESCRIPTION
    Wraps demos/demo3-xe-capture.sql (single source of truth). Drops + recreates +
    starts the `dab_mcp_capture` ring-buffer session (filtered to the ProductComponents
    view's queries in AdventureWorks), then verifies it is RUNNING and prints the SSMS
    attach steps. Idempotent — safe to run repeatedly.

    Run this BEFORE the Demo 3 cold open so the session is already streaming when you
    attach SSMS. Location-independent (uses $PSScriptRoot).

.PARAMETER Stop
    Drop the capture session (cleanup after the demo).

.EXAMPLE
    ./start-xe-capture.ps1            # create + start, ready for SSMS Watch Live Data
    ./start-xe-capture.ps1 -Stop      # drop the session
#>
[CmdletBinding()]
param(
    [string]$Server   = 'localhost',
    [string]$Database = 'AdventureWorks',
    [switch]$Stop
)

$ErrorActionPreference = 'Stop'
$here    = $PSScriptRoot
$sqlFile = Join-Path $here '..\demos\demo3-xe-capture.sql'

if ($Stop) {
    sqlcmd -S $Server -d $Database -E -C -Q "IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name=N'dab_mcp_capture') DROP EVENT SESSION [dab_mcp_capture] ON SERVER; PRINT 'dab_mcp_capture dropped';" | Out-Null
    Write-Host "XE capture stopped/dropped (dab_mcp_capture)." -ForegroundColor Yellow
    return
}

if (-not (Test-Path $sqlFile)) { throw "XE capture script not found: $sqlFile" }

Write-Host "Creating + starting XE capture (dab_mcp_capture) ..." -ForegroundColor Yellow
sqlcmd -S $Server -d $Database -E -C -i $sqlFile | Out-Null

$state = sqlcmd -S $Server -d $Database -E -C -h -1 -W -Q "SET NOCOUNT ON; SELECT CASE WHEN EXISTS (SELECT 1 FROM sys.dm_xe_sessions WHERE name=N'dab_mcp_capture') THEN 'RUNNING' ELSE 'NOT-RUNNING' END;"
if ($state -notmatch 'RUNNING') { throw "dab_mcp_capture did not start (state: $state)." }

Write-Host ""
Write-Host "XE CAPTURE: GREEN - dab_mcp_capture is RUNNING on $Server / $Database" -ForegroundColor Green
Write-Host "Attach it in SSMS before the cold open:" -ForegroundColor Cyan
Write-Host "  Object Explorer -> $Server -> Management -> Extended Events -> Sessions"
Write-Host "  Right-click 'dab_mcp_capture' -> Watch Live Data  (Refresh Sessions if not listed)"
Write-Host "Then run the cold open in Copilot Chat:"
Write-Host "  'What parts make up the Touring-1000 bike?'"
Write-Host "Watch: describe_entities -> nothing; read_records -> one rpc_completed with a bound @param0."
Write-Host "Cleanup after:  ./start-xe-capture.ps1 -Stop"
