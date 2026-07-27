#requires -Version 7.0
<#
    SQL MCP Server talk — Demo 2 reset: back up / restore dab-config.json.

    Demo 2's live fix EDITS dab-config.json (the agent adds `fields` blocks). To run
    Demo 2 again you must restore the pristine "12 warnings" starting state. This
    script snapshots and restores that config from a committed baseline copy
    (dab/dab-config.baseline.json) — independent of git working-tree state.

    Usage:
      ./reset-dab-config.ps1            # RESTORE baseline -> dab-config.json, validate, restart DAB
      ./reset-dab-config.ps1 -NoRestart # restore + validate only (skip DAB restart)
      ./reset-dab-config.ps1 -Save      # BACKUP: capture the CURRENT dab-config.json as the baseline
      ./reset-dab-config.ps1 -ApplyFields # DEMO 2 payoff: drop in the fields-filled config (0 warnings), restart
      ./reset-dab-config.ps1 -ApplyTool   # DEMO 4 payoff: switch to the FULL config (all field fixes + the get_product_bom custom tool), restart

    Typical flow:
      1. Once, when the config is in the pristine Demo-2 start state:  ./reset-dab-config.ps1 -Save
      2. Run Demo 2 (agent edits the config).
      3. To run it again:  ./reset-dab-config.ps1   (restores pristine + restarts).
#>
[CmdletBinding()]
param(
    [switch]$NoRestart,
    [switch]$Save,
    [switch]$ApplyFields,
    [switch]$ApplyTool
)

$ErrorActionPreference = 'Stop'
$here     = $PSScriptRoot
$live     = Join-Path $here 'dab/dab-config.json'
$baseline = Join-Path $here 'dab/dab-config.baseline.json'
$fields   = Join-Path $here 'dab/dab-config.fields.json'
$tool     = Join-Path $here 'dab/dab-config.tool.json'

if (-not (Test-Path $live)) { throw "Live config not found: $live" }

# --- BACKUP mode -------------------------------------------------------------
if ($Save) {
    Copy-Item $live $baseline -Force
    Write-Host "BACKUP: saved current dab-config.json as baseline ->" -ForegroundColor Green
    Write-Host "  $baseline" -ForegroundColor Green
    return
}

# --- APPLY-FIELDS mode (Demo 2 live fix, pre-built for speed) -----------------
# Instantly drops in the pre-authored fields-filled config instead of hand-editing
# live. Use as the Demo 2 payoff: agent 'adds the fields' in one move.
if ($ApplyFields) {
    if (-not (Test-Path $fields)) { throw "Fields config not found: $fields" }
    Copy-Item $fields $live -Force
    Write-Host "APPLY: fields-filled dab-config.json applied (all 9 tables + 3 stored procs now describe their columns)." -ForegroundColor Green

    $env:DAB_CONNECTION_STRING = "Server=localhost;Database=AdventureWorks;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;"
    Write-Host "`nValidating applied config ..." -ForegroundColor Yellow
    $out = dab validate -c $live 2>&1
    $out | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "dab validate failed after apply (exit $LASTEXITCODE)." }
    $warnCount = ($out | Select-String "missing 'fields'").Count
    Write-Host "`nApplied config is valid ($warnCount 'missing fields' warnings remaining = clean)." -ForegroundColor Green

    if ($NoRestart) {
        Write-Host "-NoRestart set; DAB not restarted. Run ./start-mcp-http.ps1 -Restart before demoing." -ForegroundColor Yellow
    }
    else {
        & (Join-Path $here 'start-mcp-http.ps1') -Restart
    }
    return
}

# --- APPLY-TOOL mode (Demo 4 payoff, pre-built switch) ------------------------
# Switches to the FULL final config: all 9 tables + 3 procs described (0 warnings)
# PLUS the get_product_bom custom tool over dbo.uspGetProductBOM. Self-contained —
# no live editing. The proc is already in the DB from setup.ps1 (step 3b).
if ($ApplyTool) {
    if (-not (Test-Path $tool)) { throw "Tool config not found: $tool" }
    Copy-Item $tool $live -Force
    Write-Host "APPLY: full config switched in (all field fixes + get_product_bom custom tool over dbo.uspGetProductBOM)." -ForegroundColor Green

    $env:DAB_CONNECTION_STRING = "Server=localhost;Database=AdventureWorks;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;"
    Write-Host "`nValidating applied config ..." -ForegroundColor Yellow
    $out = dab validate -c $live 2>&1
    $out | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "dab validate failed after apply (exit $LASTEXITCODE)." }
    $warnCount = ($out | Select-String "missing 'fields'").Count
    Write-Host "`nApplied config is valid ($warnCount 'missing fields' warnings = clean; get_product_bom appears in tools/list after restart)." -ForegroundColor Green

    if ($NoRestart) {
        Write-Host "-NoRestart set; DAB not restarted. Run ./start-mcp-http.ps1 -Restart before demoing." -ForegroundColor Yellow
    }
    else {
        & (Join-Path $here 'start-mcp-http.ps1') -Restart
    }
    return
}

# --- RESTORE mode ------------------------------------------------------------
if (-not (Test-Path $baseline)) {
    throw "No baseline found: $baseline`nRun './reset-dab-config.ps1 -Save' first (with the config in its pristine Demo-2 start state)."
}

Copy-Item $baseline $live -Force
Write-Host "RESTORE: dab-config.json restored from baseline." -ForegroundColor Green

# Confirm it's the expected pristine state (valid + the 12 'missing fields' warnings).
$env:DAB_CONNECTION_STRING = "Server=localhost;Database=AdventureWorks;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;"
Write-Host "`nValidating restored config ..." -ForegroundColor Yellow
$out = dab validate -c $live 2>&1
$out | Write-Host
if ($LASTEXITCODE -ne 0) { throw "dab validate failed after restore (exit $LASTEXITCODE)." }
$warnCount = ($out | Select-String "missing 'fields'").Count
Write-Host "`nRestored config is valid ($warnCount 'missing fields' warnings = Demo 2 start state)." -ForegroundColor Green

# --- Restart DAB so the restored config is live (mandatory unless -NoRestart) --
if ($NoRestart) {
    Write-Host "-NoRestart set; DAB not restarted. Run ./start-mcp-http.ps1 -Restart before demoing." -ForegroundColor Yellow
}
else {
    & (Join-Path $here 'start-mcp-http.ps1') -Restart
}
