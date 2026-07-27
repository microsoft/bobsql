#requires -Version 7.0
<#
    SQL MCP Server talk — ONE-SHOT BUILD for a fresh laptop.

    Chains the whole build so a new person runs exactly ONE command to prepare
    the environment, then start-mcp-http.ps1 to go live. Idempotent where the
    underlying scripts allow (re-running restore just re-restores AdventureWorks).

    Steps:
      1. Download AdventureWorks2022.bak (git-ignored; skipped if already present).
      2. Restore it as [AdventureWorks] (local SQL Server 2025, Windows auth).
      3. Deploy the mcp schema + mcp.vProductComponents view.
      4. Validate dab-config.json (dab validate; installs the DAB CLI if missing).

    Prereqs the HOST must already have (this script does NOT install them):
      - SQL Server 2025 local instance on localhost, Windows auth, current login = sysadmin
      - sqlcmd on PATH, .NET SDK, PowerShell 7+

    Usage:
      ./setup.ps1
      ./setup.ps1 -Server localhost -Database AdventureWorks

    Then go live:
      ./start-mcp-http.ps1
#>
[CmdletBinding()]
param(
    [string]$Server   = 'localhost',
    [string]$Database = 'AdventureWorks'
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

function Step($n, $msg) { Write-Host "`n=== [$n] $msg ===" -ForegroundColor Cyan }

# --- 0. Host prereqs (report only) -------------------------------------------
Step 0 'Checking host prerequisites'
$missing = @()
foreach ($cmd in 'sqlcmd', 'dotnet', 'pwsh') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { $missing += $cmd }
}
if ($missing.Count) { throw "Missing required tools: $($missing -join ', '). Install them, then re-run." }
$v = sqlcmd -S $Server -E -C -h -1 -W -Q "SET NOCOUNT ON; SELECT 1;" 2>&1
if ($LASTEXITCODE -ne 0) { throw "Cannot reach SQL Server on '$Server' via Windows auth. Start the instance / fix auth, then re-run." }
Write-Host "  Host OK: sqlcmd, dotnet, pwsh present; SQL reachable on $Server." -ForegroundColor Green

# --- 1. Download (sub-script throws on failure) ------------------------------
Step 1 'Download AdventureWorks backup'
& (Join-Path $here 'download-adventureworks.ps1')

# --- 2. Restore (sub-script throws on failure) -------------------------------
Step 2 'Restore [AdventureWorks]'
& (Join-Path $here 'restore-adventureworks.ps1')

# --- 3. Deploy the opener view (native sqlcmd -> check exit code) -------------
Step 3 'Deploy mcp.vProductComponents view'
sqlcmd -S $Server -E -C -b -d $Database -i (Join-Path $here 'sql/01-mcp-views.sql')
if ($LASTEXITCODE -ne 0) { throw "View deploy failed (sqlcmd exit $LASTEXITCODE)." }
Write-Host "  View deployed." -ForegroundColor Green

# --- 3b. Deploy the Demo 4 custom-tool source proc ---------------------------
Step '3b' 'Deploy dbo.uspGetProductBOM (Demo 4 custom tool)'
sqlcmd -S $Server -E -C -b -d $Database -i (Join-Path $here 'sql/02-demo4-bom-proc.sql')
if ($LASTEXITCODE -ne 0) { throw "BOM proc deploy failed (sqlcmd exit $LASTEXITCODE)." }
Write-Host "  uspGetProductBOM deployed." -ForegroundColor Green

# --- 4. Validate the DAB config (sub-script throws on failure) ----------------
Step 4 'Validate dab-config.json'
& (Join-Path $here 'build.ps1') -NoStart

Write-Host "`nSETUP COMPLETE." -ForegroundColor Green
Write-Host "Go live with:  ./start-mcp-http.ps1" -ForegroundColor Cyan
