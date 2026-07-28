<#
.SYNOPSIS
    Run one or more of the build/sql/*.sql object scripts, in order, against the
    Ward General database — passwordless (Entra token) and GO-aware (sqlsim).

.DESCRIPTION
    The single PowerShell driver for deploying the in-database objects, so the
    deploy skills are fully script-driven instead of "run these by hand in a
    client that honors GO". Used by both deploy-wardgeneral-db (schema + seed)
    and deploy-wardgeneral-ai (in-engine AI).

    For each name in -Scripts it resolves build/sql/<name>.sql, acquires a fresh
    Entra access token (never hands sqlsim an empty -T), runs the file with
    sqlsim (`-stoponerror`, so the first failing batch aborts the script) and
    reports PASS/FAIL from sqlsim's exit code (0 = success, 1 = error). Stops on
    the first failing script unless -ContinueOnError.

.PARAMETER Scripts
    Ordered list of script base names (with or without the .sql extension), e.g.
    01-schemas,02-tables,03-views,04-procedures,05-seed

.PARAMETER ContinueOnError
    Keep going after a failing script (default: stop on first failure).

.EXAMPLE
    # Schema + seed (deploy-wardgeneral-db)
    .\deploy-sql.ps1 -Scripts 01-schemas,02-tables,03-views,04-procedures,05-seed

.EXAMPLE
    # In-engine AI objects (deploy-wardgeneral-ai)
    .\deploy-sql.ps1 -Scripts 06-ai-embeddings,07-ai-assistance

.EXAMPLE
    # Verify
    .\deploy-sql.ps1 -Scripts connect-and-verify,verify-data
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]] $Scripts,
    [string]   $Server   = ($env:WG_SERVER   ?? 'collierhealth-17.database.windows.net'),
    [string]   $Database = ($env:WG_DATABASE ?? 'wardgeneral'),
    [string]   $SqlDir,
    [string]   $SqlSim,
    [switch]   $ContinueOnError
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# SQL folder: the presentation kit nests scripts under ../sql; a flat (book) example
# folder co-locates the .sql files next to this script. Support both.
if (-not $SqlDir) {
    $nested = Join-Path $here '..' 'sql'
    $SqlDir = if (Test-Path $nested) { (Resolve-Path $nested).Path } else { $here }
}
# sqlsim: bundled with the presentation kit (../../utilities/sqlsim), else on PATH,
# else the local dev build path.
if (-not $SqlSim) {
    $bundled = Join-Path $here '..' '..' 'utilities' 'sqlsim' 'sqlsim.exe'
    $onPath  = (Get-Command sqlsim.exe -ErrorAction SilentlyContinue).Source
    $built   = 'C:\bwsql\sqlsimtools\sqlsim\build\x64\Release\sqlsim.exe'
    $SqlSim  = if (Test-Path $bundled) { (Resolve-Path $bundled).Path } elseif ($onPath) { $onPath } elseif (Test-Path $built) { $built } else { $bundled }
}
if (-not (Test-Path $SqlSim)) { throw "sqlsim not found at $SqlSim (pass -SqlSim, or put sqlsim.exe on PATH)." }

function Get-DbToken {
    # Entra token for Azure SQL, waiting through transient CLI/network blips so we
    # never hand sqlsim an empty -T. $null only after being offline for the window.
    param([int]$MaxWaitMinutes = 15)
    $deadline = (Get-Date).AddMinutes($MaxWaitMinutes)
    $delay = 5
    while ($true) {
        $t = (az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv 2>$null)
        if ($t) { $t = $t.Trim() }
        if ($t -and $t.Length -gt 100 -and $t -notmatch '\s') { return $t }
        if ((Get-Date) -ge $deadline) { return $null }
        Write-Host "  Entra token unavailable - retrying in ${delay}s..." -ForegroundColor Gray
        Start-Sleep -Seconds $delay
        if ($delay -lt 30) { $delay = [math]::Min(30, $delay * 2) }
    }
}

# Resolve every script up front so a typo fails before we run anything.
$files = foreach ($name in $Scripts) {
    $leaf = if ($name.EndsWith('.sql')) { $name } else { "$name.sql" }
    $path = Join-Path $SqlDir $leaf
    if (-not (Test-Path $path)) { throw "SQL script not found: $path" }
    [pscustomobject]@{ Name = $leaf; Path = $path }
}

Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ' Deploy SQL objects'                            -ForegroundColor Cyan
Write-Host "  Server : $Server / $Database"                 -ForegroundColor Gray
Write-Host "  sqlsim : $SqlSim"                             -ForegroundColor Gray
Write-Host "  Order  : $($files.Name -join ' -> ')"         -ForegroundColor Gray
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ''

$failed = 0
foreach ($f in $files) {
    Write-Host "-> $($f.Name)" -ForegroundColor Yellow
    $token = Get-DbToken
    if (-not $token) { throw 'Could not acquire an Entra token for Azure SQL (az login?).' }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $out  = & $SqlSim -S $Server -d $Database -T $token -N s -stoponerror -i $f.Path 2>&1 | Out-String
    $code = $LASTEXITCODE
    $sw.Stop()

    if ($code -ne 0) {
        $failed++
        Write-Host "   FAIL (exit $code, $([int]$sw.Elapsed.TotalSeconds)s)" -ForegroundColor Red
        Write-Host ($out.Trim()) -ForegroundColor Red
        if (-not $ContinueOnError) { Write-Host ''; Write-Host "Stopped at $($f.Name)." -ForegroundColor Red; exit 1 }
    } else {
        Write-Host "   PASS ($([int]$sw.Elapsed.TotalSeconds)s)" -ForegroundColor Green
        $tail = ($out -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 2 | Out-String).Trim()
        if ($tail) { Write-Host "   $tail" -ForegroundColor DarkGray }
    }
    Write-Host ''
}

Write-Host '=============================================' -ForegroundColor Cyan
if ($failed -eq 0) {
    Write-Host " All $($files.Count) script(s) PASSED." -ForegroundColor Green
    exit 0
} else {
    Write-Host " $failed of $($files.Count) script(s) FAILED." -ForegroundColor Red
    exit 1
}
