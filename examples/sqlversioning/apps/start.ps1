<#
.SYNOPSIS
Starts or reuses the local SQL versioning app and opens a new normal browser window.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^(localhost|127\.0\.0\.1|\.)(\\[A-Za-z0-9_]+)?$')]
    [string]$ServerName = 'localhost',
    [ValidateRange(1024, 65535)]
    [int]$Port = 5080,
    [switch]$NoBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$baseUrl = "http://127.0.0.1:$Port"
$process = $null

function Get-AppCatalog {
    try {
        return Invoke-RestMethod "$baseUrl/api/catalog" -TimeoutSec 5
    }
    catch [System.Net.Http.HttpRequestException] {
        Write-Verbose "App is not responding yet: $($_.Exception.Message)"
        return $null
    }
    catch [System.Net.WebException] {
        Write-Verbose "App is not responding yet: $($_.Exception.Message)"
        return $null
    }
}

function Confirm-AppCatalog {
    param($Catalog)
    if (-not $Catalog.PSObject.Properties['demos'] -or
        -not $Catalog.PSObject.Properties['server'] -or
        (($Catalog.demos.id | Sort-Object) -join ',') -ne '0,1,2,3,4') {
        throw "Port $Port is not serving the expected SQL versioning app."
    }
    if ($Catalog.server -ne $ServerName) {
        throw "The running app uses '$($Catalog.server)', not '$ServerName'. End its sessions and stop it before changing targets."
    }
}

$catalog = Get-AppCatalog
if ($null -eq $catalog) {
    $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($listener) {
        throw "Port $Port is occupied but the app is not responsive. Do not start a duplicate server; inspect the existing process."
    }
    $python = (Get-Command python -CommandType Application -ErrorAction Stop |
        Select-Object -First 1).Source
    $appPath = Join-Path $PSScriptRoot 'app.py'
    $logDirectory = Join-Path $env:LOCALAPPDATA 'bobsql\sqlversioning'
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $stdoutPath = Join-Path $logDirectory "app-$Port.stdout.log"
    $stderrPath = Join-Path $logDirectory "app-$Port.stderr.log"
    $process = Start-Process -FilePath $python -WorkingDirectory $PSScriptRoot `
        -ArgumentList @('-u', "`"$appPath`"", '--server', $ServerName, '--port', $Port) `
        -WindowStyle Hidden -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        Start-Sleep -Milliseconds 500
        $process.Refresh()
        if ($process.HasExited) {
            $startupError = Get-Content -LiteralPath $stderrPath -Tail 20 | Out-String
            throw "The app exited with code $($process.ExitCode). Check '$stdoutPath' and '$stderrPath'; install requirements only if dependencies are missing.`n$startupError"
        }
        $catalog = Get-AppCatalog
    } while ($null -eq $catalog -and [DateTime]::UtcNow -lt $deadline)
    if ($null -eq $catalog) {
        throw "App process $($process.Id) started but did not become ready. Inspect '$stdoutPath' and '$stderrPath' before retrying."
    }
}
Confirm-AppCatalog $catalog
$state = Invoke-RestMethod "$baseUrl/api/state" -TimeoutSec 10
if ($state.monitor.error) {
    Write-Warning "The app is running, but SQL monitoring failed: $($state.monitor.error)"
}

if (-not $NoBrowser) {
    $browserPaths = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    $browser = $browserPaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $browser) {
        throw "App is ready at $baseUrl, but Edge/Chrome was not found. Open it in a new normal browser window; do not substitute the VS Code browser."
    }
    Start-Process -FilePath $browser -ArgumentList '--new-window', $baseUrl
}
Write-Output "SQL versioning app ready: $baseUrl"
if ($process) {
    Write-Output "Backend PID: $($process.Id). Running in the background; no inactivity expiry."
    Write-Output "Logs: $stdoutPath and $stderrPath"
}
