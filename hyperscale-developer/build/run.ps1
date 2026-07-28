#requires -Version 7.0
<#
    Ward General — run the WHOLE demo (web app + Data API Builder) and open it in
    your DEFAULT (external) browser.

    Brings up:
      * Data API Builder (REST/GraphQL/SQL MCP) on http://localhost:5000  (the chat/agent needs it)
      * the Blazor web app on https://localhost:7170

    Usage:
      ./run.ps1                 # start DAB + app and open the browser
      ./run.ps1 -NoDab          # app only (chat/agent will not work)
      ./run.ps1 -NoBrowser      # start, don't open a browser
      ./run.ps1 -OpenOnly       # just open the browser (already running)

    Ctrl+C stops the app AND DAB. (shutdown.ps1 is a backstop.)
#>
[CmdletBinding()]
param(
    [string]$HttpsUrl = 'https://localhost:7170',
    [string]$HttpUrl = 'http://localhost:5170',
    [string]$Server = 'collierhealth-17.database.windows.net',
    [string]$Database = 'wardgeneral',
    [switch]$NoBrowser,
    [switch]$OpenOnly,
    [switch]$NoDab
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$proj = Join-Path $root 'src' 'WardGeneral.Web' 'WardGeneral.Web.csproj'
$port = ([Uri]$HttpsUrl).Port

function Test-Listening([int]$p) {
    try {
        $c = [System.Net.Sockets.TcpClient]::new()
        $c.Connect('localhost', $p); $c.Close(); return $true
    }
    catch { return $false }
}

# -- Just open the browser (app is already running) -------------------------
if ($OpenOnly) {
    Start-Process $HttpsUrl
    Write-Host "Opened $HttpsUrl in your default browser." -ForegroundColor Green
    return
}

if (-not (Test-Path $proj)) { throw "Web project not found: $proj" }

# If something is already listening on the port, don't try to start a second
# instance — just open the browser.
if (Test-Listening $port) {
    Write-Host "App already listening on $HttpsUrl — opening the browser." -ForegroundColor Yellow
    Start-Process $HttpsUrl
    return
}

$env:ASPNETCORE_ENVIRONMENT = 'Development'

# -- Dependency: Data API Builder (SQL MCP at :5000) — the chat/agent needs it ----
# NOTE: ASPNETCORE_URLS is deliberately NOT set yet. DAB is itself a Kestrel app
# and would inherit it, binding to the web app's ports instead of 5000. We give
# DAB its own URL here and set the web app's URLs only just before 'dotnet run'.
$dabProc = $null
if (-not $NoDab) {
    if (-not (Get-Command dab -ErrorAction SilentlyContinue)) {
        Write-Warning "DAB CLI not found — starting WITHOUT DAB; the chat/agent will fail (localhost:5000 refused). Run ./build.ps1 or ./dab/setup-dab.ps1 to install it."
    }
    elseif (Test-Listening 5000) {
        Write-Host "DAB already listening on http://localhost:5000." -ForegroundColor Yellow
    }
    else {
        $dabConfig = Join-Path $root 'dab' 'dab-config.json'
        $dabLog = Join-Path $root 'dab' 'dab.log'
        $dabErr = Join-Path $root 'dab' 'dab.err.log'
        $env:DAB_CONNECTION_STRING =
            "Server=tcp:$Server,1433;Database=$Database;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;"
        # Pin DAB to its own port so it never collides with the web app.
        $env:ASPNETCORE_URLS = 'http://localhost:5000'
        Write-Host "Starting Data API Builder (REST/GraphQL/MCP) on http://localhost:5000 ..." -ForegroundColor Cyan
        Write-Host "  (first start can take ~60s: Entra sign-in + reflecting 13 procs; logs -> $dabLog)" -ForegroundColor DarkGray
        # Run hidden with output redirected to a log file — no scary popup window.
        $dabProc = Start-Process -FilePath 'dab' -ArgumentList @('start', '-c', $dabConfig) `
            -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $dabLog -RedirectStandardError $dabErr
        $dabUp = $false
        foreach ($i in 1..180) {
            if ($dabProc.HasExited) { break }
            if (Test-Listening 5000) { $dabUp = $true; break }
            Start-Sleep -Milliseconds 500
        }
        if ($dabUp) {
            Write-Host "DAB is up on :5000 (MCP at /mcp)." -ForegroundColor Green
        }
        elseif ($dabProc.HasExited) {
            Write-Warning "DAB exited during startup (exit $($dabProc.ExitCode)). See $dabErr / $dabLog."
            $dabProc = $null
        }
        else {
            Write-Warning "DAB did not reach :5000 within 90s — the chat/agent may fail. See $dabLog."
        }
    }
}

if (-not $NoBrowser) {
    # Wait for the app to start listening, then open the default browser — in a
    # background job so 'dotnet run' can hold the foreground.
    Start-Job -Name 'wardgeneral-open-browser' -ArgumentList $HttpsUrl, $port -ScriptBlock {
        param($url, $p)
        foreach ($i in 1..120) {
            try {
                $c = [System.Net.Sockets.TcpClient]::new()
                $c.Connect('localhost', $p); $c.Close()
                Start-Process $url
                return
            }
            catch { Start-Sleep -Milliseconds 500 }
        }
    } | Out-Null
}

# Now bind the web app to its own ports (DAB already claimed 5000).
$env:ASPNETCORE_URLS = "$HttpsUrl;$HttpUrl"
Write-Host "Starting Ward General web app on $HttpsUrl (also $HttpUrl)..." -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop (DAB is stopped automatically)." -ForegroundColor DarkGray
try {
    dotnet run --project $proj --no-launch-profile
}
finally {
    if ($dabProc -and -not $dabProc.HasExited) {
        Write-Host "Stopping DAB (pid $($dabProc.Id))..." -ForegroundColor DarkGray
        Stop-Process -Id $dabProc.Id -Force -ErrorAction SilentlyContinue
    }
    Get-Job -Name 'wardgeneral-open-browser' -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
}
