#requires -Version 7.0
<#
    SQL MCP Server talk — one-command GO LIVE (HTTP MCP surface).

    This is the "no startup worries" path. It:
      1. Runs verify-preflight.ps1 (DB up, 504, view=14, DAB CLI, config valid). Aborts on RED.
      2. Starts Data API builder as a BACKGROUND HTTP process on :5001 (REST + GraphQL + MCP).
      3. Waits until the /mcp endpoint actually answers before returning GREEN.

    Because the MCP surface is now HTTP, VS Code just CONNECTS to
    http://localhost:5001/mcp (registered in .vscode/mcp.json) — there is no stdio
    server to start by hand, and no cold-start race. Run this, see GREEN, present.

    Usage:
      ./start-mcp-http.ps1            # start (idempotent — reuses a healthy server)
      ./start-mcp-http.ps1 -Stop     # stop the background DAB HTTP process
      ./start-mcp-http.ps1 -Restart  # stop then start

    Notes:
      - Port 5001 (not 5000) so it never collides with the Ward General DAB.
      - Logs: build/artifacts/dab-http.log
#>
[CmdletBinding()]
param(
    [string]$Server   = 'localhost',
    [string]$Database = 'AdventureWorks',
    [int]$Port        = 5001,
    [string]$Config   = (Join-Path $PSScriptRoot 'dab/dab-config.json'),
    [int]$TimeoutSec  = 30,
    [switch]$Stop,
    [switch]$Restart
)

$ErrorActionPreference = 'Stop'
$McpUrl  = "http://localhost:$Port/mcp"
$BaseUrl = "http://localhost:$Port"
$LogFile = Join-Path $PSScriptRoot 'artifacts/dab-http.log'

function Get-DabOnPort {
    # Return the DAB process bound to $Port, if any.
    $conn = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $conn) { return $null }
    return Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
}

function Stop-Dab {
    $p = Get-DabOnPort
    if ($p) {
        Write-Host "Stopping DAB HTTP (pid $($p.Id)) on :$Port ..." -ForegroundColor Yellow
        $p | Stop-Process -Force
        Start-Sleep -Milliseconds 300
        Write-Host "Stopped." -ForegroundColor Green
    }
    else {
        Write-Host "No DAB HTTP process on :$Port." -ForegroundColor DarkGray
    }
}

# --- Stop / Restart handling -------------------------------------------------
if ($Stop)    { Stop-Dab; return }
if ($Restart) { Stop-Dab }

# --- 0. If a healthy server is already up, reuse it --------------------------
$existing = Get-DabOnPort
if ($existing -and -not $Restart) {
    try {
        Invoke-WebRequest -Uri $BaseUrl -TimeoutSec 3 -SkipHttpErrorCheck | Out-Null
        Write-Host "DAB HTTP already running on :$Port (pid $($existing.Id)). Reusing." -ForegroundColor Green
        Write-Host "MCP endpoint: $McpUrl" -ForegroundColor Cyan
        return
    }
    catch { Write-Host "Process on :$Port not responding — restarting it." -ForegroundColor Yellow; Stop-Dab }
}

# --- 1. Pre-flight checks (abort on RED) -------------------------------------
& (Join-Path $PSScriptRoot 'verify-preflight.ps1') -Server $Server -Database $Database -Config $Config -NoManual
if ($LASTEXITCODE -ne 0) {
    Write-Host "`nPre-flight RED — not starting DAB. Fix the failures above." -ForegroundColor Red
    exit 1
}

# --- 2. Start DAB HTTP in the background --------------------------------------
$env:DAB_CONNECTION_STRING = "Server=$Server;Database=$Database;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;"
# Persist at User scope so `dab validate` works in ANY terminal opened during the talk,
# not only this process (non-secret integrated-auth string; new terminals pick it up).
[Environment]::SetEnvironmentVariable('DAB_CONNECTION_STRING', $env:DAB_CONNECTION_STRING, 'User')
$env:ASPNETCORE_URLS       = $BaseUrl

Write-Host "`nStarting DAB HTTP on $BaseUrl (background) ..." -ForegroundColor Yellow
$proc = Start-Process -FilePath 'dab' -ArgumentList @('start', '-c', $Config) `
    -RedirectStandardOutput $LogFile -RedirectStandardError "$LogFile.err" `
    -WindowStyle Hidden -PassThru

# --- 3. Wait for the MCP protocol to actually work (real initialize handshake) --
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$ready = $false
$handshake = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"preflight","version":"1.0"}}}'
$headers = @{ 'Accept' = 'application/json, text/event-stream' }
while ((Get-Date) -lt $deadline) {
    if ($proc.HasExited) {
        Write-Host "DAB process exited early (code $($proc.ExitCode)). See $LogFile.err" -ForegroundColor Red
        exit 1
    }
    try {
        # A bare POST only proves the port is open (returns 406). We require a REAL MCP
        # initialize response containing serverInfo — that proves the protocol works end to end.
        $r = Invoke-WebRequest -Uri $McpUrl -Method Post -Headers $headers -Body $handshake `
            -ContentType 'application/json' -TimeoutSec 3 -SkipHttpErrorCheck
        if ($r.Content -match 'serverInfo') { $ready = $true; break }
    }
    catch { }
    Start-Sleep -Milliseconds 500
}

Write-Host ''
if ($ready) {
    Write-Host "GO LIVE: GREEN — DAB HTTP up (pid $($proc.Id)); MCP initialize handshake OK at $McpUrl" -ForegroundColor Green
    Write-Host "Next: make sure VS Code has read this config against the LIVE server:" -ForegroundColor Cyan
    Write-Host "  - Fresh VS Code window  -> it auto-connects (config is valid + server is up)." -ForegroundColor Cyan
    Write-Host "  - Already open + shows Stopped -> Developer: Reload Window (ONE time, deterministic)." -ForegroundColor Cyan
    Write-Host "  - Never edit .vscode/mcp.json during the talk — that is what wedges the registration." -ForegroundColor Yellow
}
else {
    Write-Host "GO LIVE: RED — MCP handshake did not succeed on $McpUrl within ${TimeoutSec}s. See $LogFile" -ForegroundColor Red
    exit 1
}
