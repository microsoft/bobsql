#requires -Version 7.0
<#
    Ward General Hospital Digital Chart Application
    restart.ps1 : stop the running app, then start it again.

    Why this exists: run.ps1 refuses to start a second instance. If it finds
    something already listening on 7170 it just opens the browser at the app
    that is ALREADY running. That is the right behavior for a double-click, but
    it is a trap when you have changed configuration -- you get the old process
    back and the change appears not to have worked.

    Configuration is read once at startup (the feature flags are injected as
    IOptions<FeatureFlags>, a singleton), so a config change needs a real
    restart, not a page refresh. Later areas turn panels on with -Enable:

        ./restart.ps1 -Enable AiAssistance              # AI-Ready SQL (AI card + Research)
        ./restart.ps1 -Enable AiAgent                   # Agentic AI (chat icon; needs the
                                                        #   Agentic AI app evolution, and the
                                                        #   SQL MCP endpoint already running --
                                                        #   the pre-flight will refuse without it)
        ./restart.ps1 -Enable RowLevelSecurity          # Security
        ./restart.ps1 -Enable AiAssistance,AiAgent      # more than one
        ./restart.ps1                                   # back to the defaults

    Ward General App features are not flags -- the base chart, including the REGEXP_*
    note-signal card, is simply part of the app.

    -Enable is the COMPLETE list of flags to force on. Any flag not named is
    cleared back to whatever appsettings.json says, so the switch is not sticky:
    a plain ./restart.ps1 always returns the app to its shipped defaults. (It
    has to work that way -- $env: writes land in the process environment and
    would otherwise outlive the script.)

    No separate build step is involved: run.ps1 uses `dotnet run`, which compiles
    the current sources on the way up and reads
    src/WardGeneral.Web/appsettings.json from the project directory directly. So
    a restart does pick up source edits -- which is what Agentic AI relies on --
    but run build.ps1 first when you want compiler errors reported on their own
    rather than mixed into startup output.

    Usage:
      ./restart.ps1                 # stop, then start and open the browser
      ./restart.ps1 -NoBrowser      # stop, then start without a browser
      ./restart.ps1 -SkipPreflight  # skip the sign-in, firewall and DB checks
#>
[CmdletBinding()]
param(
    [string]$HttpsUrl = 'https://localhost:7170',
    [string]$HttpUrl = 'http://localhost:5170',
    [string]$Server,
    [string]$Database,
    [ValidateSet('AiAssistance', 'AiAgent', 'RowLevelSecurity')]
    [string[]]$Enable = @(),
    [switch]$NoBrowser,
    [switch]$SkipFirewall,
    [switch]$SkipPreflight
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$ports = @(([Uri]$HttpsUrl).Port, ([Uri]$HttpUrl).Port)

# -- Feature flags. ASP.NET Core maps a config path to an environment variable by
# replacing ':' with '__' (Features:AiAssistance -> Features__AiAssistance), and
# environment variables outrank appsettings.json. RowLevelSecurity is its own
# config section rather than a Features entry, so it maps differently -- but the
# reader still just names the flag. Set what was asked for, clear what wasn't.
$flagVars = [ordered]@{
    AiAssistance     = 'Features__AiAssistance'
    AiAgent          = 'Features__AiAgent'
    RowLevelSecurity = 'RowLevelSecurity__Enabled'
}

foreach ($flag in $flagVars.Keys) {
    $name = $flagVars[$flag]
    if ($Enable -contains $flag) {
        Set-Item -Path "Env:\$name" -Value 'true'
        Write-Host "Feature $flag = on" -ForegroundColor Cyan
    }
    elseif (Test-Path "Env:\$name") {
        Remove-Item -Path "Env:\$name"
    }
}

# -- Stop. shutdown.ps1 only stops a process it recognizes as the app, and
# reports anything else rather than killing it.
& (Join-Path $root 'shutdown.ps1') -Ports $ports

# -- Wait for the ports to actually free up. Stop-Process returns before the
# listener is gone, and run.ps1 would then see a stale listener and decline to
# start. A connect attempt answers "is anything still listening" on every OS,
# unlike Get-NetTCPConnection, which is Windows-only.
function Test-Listening([int]$p) {
    try {
        $c = [System.Net.Sockets.TcpClient]::new()
        $c.Connect('localhost', $p); $c.Close(); return $true
    }
    catch { return $false }
}

foreach ($i in 1..40) {
    $held = $ports | Where-Object { Test-Listening $_ }
    if (-not $held) { break }
    Start-Sleep -Milliseconds 250
}

if ($held) {
    throw "Port(s) $($held -join ', ') are still in use. Something other than the Ward General app is holding them -- see the warning above."
}

# -- Start. Pass through only what the caller actually set, so run.ps1's own
# defaults (and its appsettings.json fallback for -Server / -Database) still
# apply.
$runArgs = @{
    HttpsUrl      = $HttpsUrl
    HttpUrl       = $HttpUrl
    NoBrowser     = $NoBrowser
    SkipFirewall  = $SkipFirewall
    SkipPreflight = $SkipPreflight
}
if ($Server) { $runArgs['Server'] = $Server }
if ($Database) { $runArgs['Database'] = $Database }

& (Join-Path $root 'run.ps1') @runArgs
