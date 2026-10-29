#requires -Version 7.0
<#
    Start Ward General independently of the current terminal for local demos.

    The normal run.ps1 intentionally owns the foreground and stops when its
    terminal closes. This launcher performs the interactive preflight first,
    then starts run.ps1 in a detached PowerShell process and verifies that the
    HTTPS port is listening before it opens Microsoft Edge.

    Output is written under %LOCALAPPDATA%\WardGeneral\logs. The process does
    not survive a Windows restart; use APP-SERVICE.md when the app must be
    continuously hosted outside the demo laptop.

    Usage:
      ./start-demo.ps1
      ./start-demo.ps1 -Enable AiAssistance
      ./start-demo.ps1 -Enable AiAssistance,AiAgent
      ./shutdown.ps1
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
    [switch]$SkipPreflight,
    [ValidateRange(1, 600)]
    [int]$McpStartupTimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$port = ([Uri]$HttpsUrl).Port
$healthUrl = "{0}://{1}:{2}/healthz" -f ([Uri]$HttpsUrl).Scheme, ([Uri]$HttpsUrl).Host, $port

function Test-Listening([int]$Port) {
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $client.Connect('localhost', $Port)
        $client.Close()
        return $true
    }
    catch { return $false }
}

function Test-AppHealthy([string]$Url) {
    try {
        $response = Invoke-WebRequest -Uri $Url -SkipCertificateCheck -TimeoutSec 3
        return $response.StatusCode -eq 200
    }
    catch { return $false }
}

function Test-DemoPageReady([string]$Url) {
    try {
        $response = Invoke-WebRequest -Uri $Url -SkipCertificateCheck -TimeoutSec 90
        return $response.StatusCode -eq 200
    }
    catch {
        Write-Warning "Ward General is running, but the presentation page did not load: $($_.Exception.Message)"
        return $false
    }
}

function Open-DemoUrl([string]$Url) {
    $edgePath = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

    if ($edgePath) {
        Start-Process -FilePath $edgePath -ArgumentList '--new-window', $Url
    }
    else {
        Start-Process $Url
    }
}

& (Join-Path $root 'load-env.ps1') -Optional -Quiet
if ($Server) { $env:WardGeneral__Server = $Server }
if ($Database) { $env:WardGeneral__Database = $Database }

$flagVars = [ordered]@{
    AiAssistance     = 'Features__AiAssistance'
    AiAgent          = 'Features__AiAgent'
    RowLevelSecurity = 'RowLevelSecurity__Enabled'
}
foreach ($flag in $flagVars.Keys) {
    $name = $flagVars[$flag]
    if ($Enable -contains $flag) {
        Set-Item -Path "Env:\$name" -Value 'true'
    }
    elseif (Test-Path "Env:\$name") {
        Remove-Item -Path "Env:\$name"
    }
}

$logRoot = Join-Path $env:LOCALAPPDATA 'WardGeneral\logs'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

if ($Enable -contains 'AiAgent') {
    $mcpUrl = $env:Agent__McpUrl
    if (-not $mcpUrl) {
        $webDir = Join-Path $root 'src' 'WardGeneral.Web'
        foreach ($settingsFile in 'appsettings.Development.json', 'appsettings.json') {
            $settingsPath = Join-Path $webDir $settingsFile
            if (Test-Path $settingsPath) {
                $configuredUrl = (Get-Content $settingsPath -Raw | ConvertFrom-Json).Agent.McpUrl
                if (-not [string]::IsNullOrWhiteSpace($configuredUrl)) {
                    $mcpUrl = $configuredUrl
                    break
                }
            }
        }
    }
    if (-not $mcpUrl) { $mcpUrl = 'http://localhost:5000/mcp' }

    $mcpUri = [Uri]$mcpUrl
    if ($mcpUri.Host -notin @('localhost', '127.0.0.1', '::1')) {
        throw "start-demo.ps1 cannot own the remote MCP endpoint $mcpUrl. Start that endpoint before running the app."
    }

    $rlsEnabled = $Enable -contains 'RowLevelSecurity'
    $probe = if ($rlsEnabled) {
        Join-Path $root '..' 'security' 'rls' 'probe-secured-mcp.ps1'
    }
    else {
        Join-Path $root '..' 'agentic-ai' 'probe-mcp.ps1'
    }

    function Test-McpReady {
        if (-not (Test-Listening $mcpUri.Port)) { return $false }
        try {
            $probeArgs = @{ Url = $mcpUrl; Quiet = $true }
            if ($rlsEnabled) { $probeArgs['StartupTimeoutSeconds'] = 0 }
            $tools = @(& $probe @probeArgs 2>$null)
            return $tools.Count -gt 0
        }
        catch { return $false }
    }

    if (-not (Test-McpReady)) {
        $dabScript = if ($rlsEnabled) {
            Join-Path $root '..' 'security' 'rls' '02-run-secured-dab.ps1'
        }
        else {
            Join-Path $root '..' 'agentic-ai' 'run-dab.ps1'
        }
        if (-not (Test-Path $dabScript)) { throw "DAB launcher not found: $dabScript" }

        $dabStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $dabStdoutLog = Join-Path $logRoot "dab-$dabStamp.out.log"
        $dabStderrLog = Join-Path $logRoot "dab-$dabStamp.err.log"
        $dabCommand = "& '$($dabScript.Replace("'", "''"))' -Port $($mcpUri.Port)"
        $dabEncodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($dabCommand))
        $dabStartArgs = @{
            FilePath               = (Get-Command pwsh).Source
            ArgumentList           = @('-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', $dabEncodedCommand)
            RedirectStandardOutput = $dabStdoutLog
            RedirectStandardError  = $dabStderrLog
            PassThru               = $true
        }
        if ($IsWindows) { $dabStartArgs['WindowStyle'] = 'Hidden' }
        $dabProcess = Start-Process @dabStartArgs

        Write-Host "Starting the SQL MCP endpoint at $mcpUrl (launcher pid $($dabProcess.Id)) ..." -ForegroundColor Cyan
        $deadline = [DateTimeOffset]::UtcNow.AddSeconds($McpStartupTimeoutSeconds)
        while (-not (Test-McpReady) -and [DateTimeOffset]::UtcNow -lt $deadline) {
            if ($dabProcess.HasExited) {
                $dabError = @(
                    if (Test-Path $dabStdoutLog) { Get-Content $dabStdoutLog -Tail 30 }
                    if (Test-Path $dabStderrLog) { Get-Content $dabStderrLog -Tail 30 }
                ) -join [Environment]::NewLine
                throw "SQL MCP startup failed (code $($dabProcess.ExitCode)). Logs: $dabStdoutLog and $dabStderrLog`n$dabError"
            }
            Start-Sleep -Seconds 1
        }
        if (-not (Test-McpReady)) {
            throw "SQL MCP endpoint did not become ready at $mcpUrl within $McpStartupTimeoutSeconds seconds. Logs: $dabStdoutLog and $dabStderrLog"
        }
        Write-Host "SQL MCP endpoint is ready at $mcpUrl. Logs: $dabStdoutLog" -ForegroundColor Green
    }
}

if (Test-AppHealthy $healthUrl) {
    if (-not (Test-DemoPageReady $HttpsUrl)) {
        throw "Ward General passed its host health check, but the presentation page is not ready. Check database connectivity and retry."
    }
    Write-Host "Ward General is already healthy and warmed at $HttpsUrl." -ForegroundColor Yellow
    if (-not $NoBrowser) { Open-DemoUrl $HttpsUrl }
    return
}

if (Test-Listening $port) {
    Write-Warning "Port $port is open, but Ward General failed its health check. Attempting a clean recycle."
    & (Join-Path $root 'shutdown.ps1') -Ports @(([Uri]$HttpsUrl).Port, ([Uri]$HttpUrl).Port)
    foreach ($attempt in 1..20) {
        if (-not (Test-Listening $port)) { break }
        Start-Sleep -Milliseconds 250
    }
    if (Test-Listening $port) {
        throw "Port $port is still held by an unhealthy or unrecognized process. Run .\shutdown.ps1 and inspect the warning before retrying."
    }
}

if (-not $SkipPreflight) {
    & (Join-Path $root 'preflight-run.ps1') -Server $Server -Database $Database -SkipFirewall:$SkipFirewall
    if ($LASTEXITCODE -ne 0) {
        throw 'Run preflight failed. No background process was started.'
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdoutLog = Join-Path $logRoot "wardgeneral-$stamp.out.log"
$stderrLog = Join-Path $logRoot "wardgeneral-$stamp.err.log"
$runScript = Join-Path $root 'run.ps1'

$childCommand = "& '$($runScript.Replace("'", "''"))' -HttpsUrl '$HttpsUrl' -HttpUrl '$HttpUrl' -NoBrowser -SkipPreflight"
$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCommand))
$startArgs = @{
    FilePath               = (Get-Command pwsh).Source
    ArgumentList           = @('-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', $encodedCommand)
    RedirectStandardOutput = $stdoutLog
    RedirectStandardError  = $stderrLog
    PassThru               = $true
}
if ($IsWindows) { $startArgs['WindowStyle'] = 'Hidden' }
$process = Start-Process @startArgs

foreach ($attempt in 1..120) {
    if (Test-AppHealthy $healthUrl) { break }
    if ($process.HasExited) {
        $errorText = if (Test-Path $stderrLog) { (Get-Content $stderrLog -Tail 20) -join [Environment]::NewLine } else { '' }
        throw "Ward General exited during startup (code $($process.ExitCode)). Error log: $stderrLog`n$errorText"
    }
    Start-Sleep -Milliseconds 250
}

if (-not (Test-AppHealthy $healthUrl)) {
    throw "Ward General did not become healthy at $healthUrl within 30 seconds. Logs: $stdoutLog and $stderrLog"
}

if (-not (Test-DemoPageReady $HttpsUrl)) {
    throw "Ward General started, but the presentation page did not become ready. Check database connectivity. Logs: $stdoutLog and $stderrLog"
}

Write-Host "Ward General is running independently (launcher pid $($process.Id))." -ForegroundColor Green
Write-Host "URL:  $HttpsUrl"
Write-Host "Health: $healthUrl"
Write-Host "Logs: $stdoutLog"
Write-Host "Stop: $root\shutdown.ps1"
if (-not $NoBrowser) { Open-DemoUrl $HttpsUrl }