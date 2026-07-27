#requires -Version 7.0
<#
    SQL MCP Server talk — PRE-FLIGHT verifier.

    Run this before you present (or before a rehearsal). It asserts every
    SCRIPTABLE piece of the demo environment and prints one GREEN/RED line per
    check, then a final verdict. It changes nothing — read-only.

    What it CANNOT do: start the stdio "Adventure Works (SQL MCP)" server. That
    process is owned by VS Code (it spawns `dab start --mcp-stdio ...` on demand).
    So the last section prints the ONE manual VS Code action you still do by hand,
    every time, on stage.

    Usage:
      ./verify-preflight.ps1
      ./verify-preflight.ps1 -Server localhost -Database AdventureWorks

    Exit code: 0 if all scriptable checks pass, 1 otherwise.
#>
[CmdletBinding()]
param(
    [string]$Server   = 'localhost',
    [string]$Database = 'AdventureWorks',
    [string]$Config   = (Join-Path $PSScriptRoot 'dab/dab-config.json'),
    [version]$MinDab  = '2.0.9',
    [switch]$NoManual   # suppress the stdio MANUAL block (used by the HTTP go-live path)
)

$ErrorActionPreference = 'Stop'
$fail = $false

function Test-Step {
    param([string]$Name, [scriptblock]$Check, [string]$Expected)
    try {
        $result = & $Check
        if ($result.Ok) {
            Write-Host ("  [PASS] {0,-42} {1}" -f $Name, $result.Detail) -ForegroundColor Green
        }
        else {
            Write-Host ("  [FAIL] {0,-42} {1} (expected {2})" -f $Name, $result.Detail, $Expected) -ForegroundColor Red
            $script:fail = $true
        }
    }
    catch {
        Write-Host ("  [FAIL] {0,-42} {1}" -f $Name, $_.Exception.Message) -ForegroundColor Red
        $script:fail = $true
    }
}

Write-Host "`nSQL MCP Server — pre-flight ($Server / $Database)`n" -ForegroundColor Cyan

# --- 1. Database reachable + AdventureWorks present --------------------------
Test-Step 'DB reachable (Windows auth)' {
    $v = sqlcmd -S $Server -E -C -h -1 -W -Q "SET NOCOUNT ON; SELECT LEFT(@@VERSION,24);" 2>&1
    @{ Ok = ($LASTEXITCODE -eq 0); Detail = ($v | Select-Object -First 1) }
} 'connection succeeds'

# --- 2. Product count = 504 --------------------------------------------------
Test-Step 'Production.Product = 504' {
    $n = sqlcmd -S $Server -E -C -h -1 -W -d $Database -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM Production.Product;" 2>&1
    $n = ($n | Select-Object -First 1).Trim()
    @{ Ok = ($n -eq '504'); Detail = "$n rows" }
} '504'

# --- 3. Opener view returns 14 for Touring-1000 ------------------------------
Test-Step 'mcp.vProductComponents Touring-1000 = 14' {
    $n = sqlcmd -S $Server -E -C -h -1 -W -d $Database -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM mcp.vProductComponents WHERE ProductModel='Touring-1000';" 2>&1
    $n = ($n | Select-Object -First 1).Trim()
    @{ Ok = ($n -eq '14'); Detail = "$n components" }
} '14'

# --- 4. DAB CLI present and >= MinDab ----------------------------------------
Test-Step "DAB CLI >= $MinDab" {
    $raw = (dab --version) 2>&1 | Select-Object -First 1
    if ($raw -match '(\d+\.\d+\.\d+)') { $ver = [version]$Matches[1] } else { $ver = [version]'0.0.0' }
    @{ Ok = ($ver -ge $MinDab); Detail = $raw }
} ">= $MinDab"

# --- 5. dab validate on the config -------------------------------------------
Test-Step 'dab validate config' {
    $env:DAB_CONNECTION_STRING = "Server=$Server;Database=$Database;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;"
    $out = dab validate -c $Config 2>&1
    @{ Ok = ($LASTEXITCODE -eq 0); Detail = (($out | Select-String 'Config is valid' | Select-Object -First 1) ?? 'see output') }
} 'Config is valid'

# --- 6. How many DAB processes are up (want 0 or 1, never 2) -----------------
Test-Step 'DAB processes running (0 or 1)' {
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='dotnet.exe' OR Name='dab.exe'" |
        Where-Object { $_.CommandLine -match 'dab start|DataApiBuilder|mcp-stdio|dab-config' })
    $ok = ($procs.Count -le 1)
    $detail = if ($procs.Count -eq 0) { 'none up (VS Code will spawn stdio on demand)' }
              elseif ($procs.Count -eq 1) { "1 running (pid $($procs[0].ProcessId))" }
              else { "$($procs.Count) running — STOP the extra one" }
    @{ Ok = $ok; Detail = $detail }
} '0 or 1, never 2'

# --- Verdict -----------------------------------------------------------------
Write-Host ''
if ($fail) {
    Write-Host 'PRE-FLIGHT: RED — fix the [FAIL] lines above before presenting.' -ForegroundColor Red
}
else {
    Write-Host 'PRE-FLIGHT: GREEN — scriptable checks all pass.' -ForegroundColor Green
}

# --- The one irreducible manual step (stdio path only) -----------------------
if (-not $NoManual) {
    Write-Host ''
    Write-Host 'If using the stdio MCP server, VS Code owns the start (do it every time):' -ForegroundColor Yellow
    Write-Host '  1. MCP: List Servers  ->  STOP any OTHER SQL MCP server (only one can run at a time)' -ForegroundColor Yellow
    Write-Host '  2. MCP: List Servers  ->  START "Adventure Works (SQL MCP)"  (wait for Running, ~2-4s)' -ForegroundColor Yellow
    Write-Host '  3. Agent chat warm-up:  "List the AdventureWorks entities."  (retry ONCE if it errors)' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Prefer zero clicks? Use the HTTP path instead:  ./sqlmcpserver/build/start-mcp-http.ps1' -ForegroundColor Cyan
    Write-Host ''
}

exit ([int]$fail)
