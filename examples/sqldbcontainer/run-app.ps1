#requires -Version 7.4
<#
.SYNOPSIS
Starts the published local Service Desk and opens a standalone Edge window.
.DESCRIPTION
Runs without a visible server console, with .NET user secrets, on localhost only. No database
deployment, credential rotation, model invocation, or Azure provisioning.
#>
[CmdletBinding()]
param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$url = 'http://localhost:5187'
$publish = Join-Path $PSScriptRoot 'app\bin\publish'
$dll = Join-Path $publish 'CustomerServiceDesk.dll'
if (-not (Test-Path -LiteralPath $dll)) { throw 'Published app not found. Run build-app.ps1 first.' }
$listeners = @(Get-NetTCPConnection -LocalPort 5187 -State Listen -ErrorAction SilentlyContinue)
if ($listeners.Count -eq 0) {
    $dotnet = (Get-Command dotnet -ErrorAction Stop).Source
    $process = Start-Process -FilePath $dotnet -WorkingDirectory $publish -PassThru -WindowStyle Hidden `
        -ArgumentList @("`"$dll`"", '--contentRoot', "`"$publish`"", '--urls', $url) `
        -Environment @{ ASPNETCORE_ENVIRONMENT = 'Development' } `
        -RedirectStandardOutput (Join-Path $publish 'web.stdout.log') `
        -RedirectStandardError (Join-Path $publish 'web.stderr.log')
    Write-Host "Started Service Desk process $($process.Id)."
} else {
    foreach ($processId in @($listeners.OwningProcess | Select-Object -Unique)) {
        $existing = Get-CimInstance Win32_Process -Filter "ProcessId=$processId"
        if ($existing.CommandLine -notlike "*$dll*") {
            throw "Port 5187 is occupied by a different process ($processId). No process was stopped."
        }
    }
    Write-Host 'Reusing the running published Service Desk.'
}
$health = Invoke-RestMethod "$url/health" -MaximumRetryCount 8 -RetryIntervalSec 1 -TimeoutSec 10
if ($health.database -ne 'reachable') { throw 'The application database health check failed.' }
$page = Invoke-WebRequest $url -TimeoutSec 15
if ($page.StatusCode -ne 200 -or $page.Content -notmatch 'A clearer path to resolution') {
    throw 'The application workspace did not pass its readiness check.'
}
Write-Host "Ready: $url; cases: $($health.cases); semantic search ready: $($health.searchReady)."
if (-not $NoBrowser) {
    $edge = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $edge) { throw 'Service Desk is running, but Microsoft Edge could not be found.' }
    Start-Process -FilePath $edge -ArgumentList "--app=$url"
    Write-Host 'Opened standalone Microsoft Edge app window.'
}
