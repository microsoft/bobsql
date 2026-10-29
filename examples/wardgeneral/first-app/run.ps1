#requires -Version 7.0
<#
    Ward General Hospital Digital Chart Application
    run.ps1 : run the Blazor web app on https://localhost:7170 and open it in
    your DEFAULT (external) browser.

    Usage:
      ./run.ps1                 # start the app and open the browser
      ./run.ps1 -NoBrowser      # start, don't open a browser
      ./run.ps1 -OpenOnly       # just open the browser (already running)
      ./run.ps1 -SkipFirewall   # skip only the firewall check
      ./run.ps1 -SkipPreflight  # skip the sign-in, firewall and database checks

    The server and database are not hard-coded here. Leave -Server and -Database
    alone and the app reads them from the same layered configuration the
    pre-flight does, highest first: the WardGeneral__Server / WardGeneral__Database
    environment variables -- which wardgeneral.env populates, if you made one -- then
    src/WardGeneral.Web/appsettings.Development.json (git-ignored, where your
    values belong), then appsettings.json -- which ships with an EMPTY server on
    purpose, so no live name is ever committed.

    Passing -Server or -Database exports the matching environment variable, so the
    override reaches the app and the pre-flight alike -- one place to configure,
    not two that can drift apart.

    Ctrl+C stops the app. (shutdown.ps1 is a backstop.)

    The chat/agent panel needs the Data API Builder SQL MCP server on
    http://localhost:5000. That is Agentic AI — start it separately with
    ../agentic-ai/run-dab.ps1, in its own shell, BEFORE this script. When the
    AiAgent flag is on the pre-flight checks that endpoint and refuses to start
    without it, because an agent with no tools is a worse outcome than an app that
    declines to launch.
#>
[CmdletBinding()]
param(
    [string]$HttpsUrl = 'https://localhost:7170',
    [string]$HttpUrl = 'http://localhost:5170',
    [string]$Server,
    [string]$Database,
    [switch]$NoBrowser,
    [switch]$OpenOnly,
    [switch]$SkipFirewall,
    [switch]$SkipPreflight
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

# Opening a URL in the user's real browser is the one genuinely per-OS action in
# this script. Start-Process handles it on Windows; macOS and Linux each have
# their own launcher. Written for all three, tested on Windows.
function Open-Url([string]$u) {
    if ($IsWindows) { Start-Process $u }
    elseif ($IsMacOS) { & open $u }
    else { & xdg-open $u }
}

# -- Just open the browser (app is already running) -------------------------
if ($OpenOnly) {
    Open-Url $HttpsUrl
    Write-Host "Opened $HttpsUrl in your default browser." -ForegroundColor Green
    return
}

if (-not (Test-Path $proj)) { throw "Web project not found: $proj" }

# wardgeneral.env, if the reader made one. Loaded here as well as in the pre-flight so
# that -SkipPreflight does not silently lose the reader's configuration. Loading
# twice is harmless: the second pass sets the same values.
& (Join-Path $root 'load-env.ps1') -Optional -Quiet

# If something is already listening on the port, don't try to start a second
# instance — just open the browser.
if (Test-Listening $port) {
    Write-Host "App already listening on $HttpsUrl — opening the browser." -ForegroundColor Yellow
    Open-Url $HttpsUrl
    return
}

# -- Pre-flight: prove the app can reach its data before we start it. Azure
# sign-in, the server firewall (delegated to Getting Started's script, which prompts
# before adding a single named rule), and the database itself. A reader who is
# not signed in otherwise gets a running app that throws on the first screen.
if (-not $SkipPreflight) {
    & (Join-Path $root 'preflight-run.ps1') -Server $Server -Database $Database -SkipFirewall:$SkipFirewall
    if ($LASTEXITCODE -ne 0) {
        throw "Run pre-flight failed. Fix the problems above, or re-run with -SkipPreflight."
    }
}

$env:ASPNETCORE_ENVIRONMENT = 'Development'

# -- Where the app points. ASP.NET Core maps WardGeneral:Server to the environment
# variable WardGeneral__Server (':' becomes '__'), and environment variables outrank
# appsettings.json. Exporting them here is what makes -Server reach the APP and not
# just the pre-flight. Nothing is exported when the switches aren't used, so the
# app's own config chain (appsettings.Development.json, then appsettings.json) wins.
if ($Server) { $env:WardGeneral__Server = $Server }
if ($Database) { $env:WardGeneral__Database = $Database }

if (-not $NoBrowser) {
    # Wait for the app to start listening, then open the default browser — in a
    # background job so 'dotnet run' can hold the foreground.
    Start-Job -Name 'wardgeneral-open-browser' -ArgumentList $HttpsUrl, $port -ScriptBlock {
        param($url, $p)
        foreach ($i in 1..120) {
            try {
                $c = [System.Net.Sockets.TcpClient]::new()
                $c.Connect('localhost', $p); $c.Close()
                # A job runs in its own runspace, so Open-Url is out of scope here.
                if ($IsWindows) { Start-Process $url }
                elseif ($IsMacOS) { & open $url }
                else { & xdg-open $url }
                return
            }
            catch { Start-Sleep -Milliseconds 500 }
        }
    } | Out-Null
}

$env:ASPNETCORE_URLS = "$HttpsUrl;$HttpUrl"
Write-Host "Starting Ward General web app on $HttpsUrl (also $HttpUrl)..." -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray
try {
    dotnet run --project $proj --no-launch-profile
}
finally {
    Get-Job -Name 'wardgeneral-open-browser' -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
}
