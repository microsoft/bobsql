<#
.SYNOPSIS
    Re-anchor the Agentic AI shift window to now, then restart Ward General with
    the AiAgent flag.

.DESCRIPTION
    The two commands a reader needs whenever they come back to Agentic AI on a
    later day, in the order that matters.

    Getting Started seeds active admissions a few hours before the moment it runs, and
    clinical.GetHandoffCandidates looks back twelve hours. So on any day but
    seeding day the roster is correctly empty and turn 1 has nothing to reason
    about. 13-refresh-shift-window.sql moves the data to where the reader is
    standing; it is rerunnable and recomputes an absolute delta, so running it
    twice in a row is a no-op the second time.

    This does NOT start DAB. restart.ps1's pre-flight already refuses to start
    the app when nothing answers on the MCP endpoint, and names run-dab.ps1.

.EXAMPLE
    ./refresh-and-run.ps1
    Refresh the window, then start the app with AiAgent.

.EXAMPLE
    ./refresh-and-run.ps1 -Enable AiAssistance,AiAgent
    The whole application: AI-Ready SQL's surface alongside Agentic AI's dock.

.EXAMPLE
    ./refresh-and-run.ps1 -SkipRefresh
    Just restart - the window was refreshed earlier today.

.EXAMPLE
    ./refresh-and-run.ps1 -SkipFirewall
    Skip the firewall check. Without this, restart.ps1 may PROMPT for approval to
    add or update the server firewall rule for this client's IP - which stalls
    silently if the script was launched somewhere the prompt is not visible.
#>
[CmdletBinding()]
param(
    [string]$Server,
    [string]$Database,
    [string]$SqlCmd,
    [ValidateSet('AiAssistance', 'AiAgent', 'RowLevelSecurity')]
    [string[]]$Enable = @('AiAgent'),
    [switch]$SkipRefresh,
    [switch]$NoBrowser,
    [switch]$SkipFirewall,
    [switch]$SkipPreflight
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

Write-Host "== Ward General: refresh the shift window and run ==" -ForegroundColor Cyan

if (-not $SkipRefresh) {
    $loadEnv = Join-Path $here '..' 'first-app' 'load-env.ps1'
    if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }

    if (-not $Server)   { $Server   = $env:WardGeneral__Server }
    if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
    if (-not $Server) {
        throw 'No server. Fill in WardGeneral__Server in first-app/wardgeneral.env, or pass -Server <your-server>.database.windows.net.'
    }

    # go-sqlcmd, not the legacy ODBC build. Both answer to `sqlcmd` and both take
    # -G, but only go-sqlcmd's -G is DefaultAzureCredential. `--version` succeeds
    # on go-sqlcmd alone, which is the only reliable way to tell them apart.
    $isGoSqlcmd = {
        param($exe)
        if (-not $exe) { return $false }
        & $exe --version 2>&1 | Out-Null
        return $LASTEXITCODE -eq 0
    }

    $sqlcmdPath = @(
        $SqlCmd,
        $env:SQLCMD,
        (Join-Path $env:LOCALAPPDATA 'Programs\sqlcmd\sqlcmd.exe'),
        'C:\Program Files\sqlcmd\sqlcmd.exe',
        (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
    ) | Where-Object { $_ -and (Test-Path $_) -and (& $isGoSqlcmd $_) } | Select-Object -First 1

    if (-not $sqlcmdPath) {
        throw @"
go-sqlcmd not found - cannot refresh the shift window.

Agentic AI needs go-sqlcmd (sqlcmd v1.x), not the legacy ODBC sqlcmd. Only
go-sqlcmd's -G resolves DefaultAzureCredential, which is the same passwordless
identity the application and DAB already use.

  winget install --id Microsoft.Sqlcmd

No admin? Unzip the release and point at it:
  https://github.com/microsoft/go-sqlcmd/releases
  `$env:SQLCMD = 'C:\path\to\sqlcmd.exe'

Looked in: -SqlCmd, `$env:SQLCMD, %LOCALAPPDATA%\Programs\sqlcmd, C:\Program Files\sqlcmd, PATH.
If you have the ODBC sqlcmd on PATH it was skipped on purpose - `sqlcmd --version`
succeeds only on go-sqlcmd.

Or run 13-refresh-shift-window.sql yourself and re-run with -SkipRefresh.
"@
    }

    $script = Join-Path $here '13-refresh-shift-window.sql'
    if (-not (Test-Path $script)) { throw "Missing SQL script: $script" }

    Write-Host "SQL runner: $sqlcmdPath" -ForegroundColor Green
    Write-Host "Re-anchoring the shift window on $Database ..." -ForegroundColor Yellow
    & $sqlcmdPath -S $Server -d $Database -G -C -b -i $script
    if ($LASTEXITCODE -ne 0) { throw "Refresh failed (sqlcmd exit $LASTEXITCODE)." }
    Write-Host "Shift window re-anchored." -ForegroundColor Green
}
else {
    Write-Host "Skipping the refresh (-SkipRefresh)." -ForegroundColor DarkGray
}

$restart = Join-Path $here '..' 'first-app' 'restart.ps1'
if (-not (Test-Path $restart)) { throw "Missing $restart" }

Write-Host "Restarting Ward General with: $($Enable -join ', ')" -ForegroundColor Yellow
Write-Host "(restart.ps1 may prompt to add or update the server firewall rule - answer it, or re-run with -SkipFirewall.)" -ForegroundColor DarkGray
$restartArgs = @{ Enable = $Enable }
if ($Server)        { $restartArgs.Server   = $Server }
if ($Database)      { $restartArgs.Database = $Database }
if ($NoBrowser)     { $restartArgs.NoBrowser = $true }
if ($SkipFirewall)  { $restartArgs.SkipFirewall = $true }
if ($SkipPreflight) { $restartArgs.SkipPreflight = $true }
& $restart @restartArgs
