[CmdletBinding()]
param(
    [switch]$Open
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"

$failures = 0
foreach ($path in '/healthz', '/', '/serverless-illustration', '/network', '/verify', '/appointments') {
    $uri = "$AppUrl$path"
    try {
        $response = $null
        for ($attempt = 1; $attempt -le 6 -and -not $response; $attempt++) {
            try { $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 60 }
            catch { if ($attempt -eq 6) { throw }; Start-Sleep -Seconds 10 }
        }
        Write-Ok "$path -> HTTP $($response.StatusCode)"
        if ($path -eq '/healthz') { Write-Skip "    $($response.Content)" }
    }
    catch {
        $failures++
        Write-Host "    $path -> FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }
}

if ($failures -gt 0) { throw "$failures endpoint check(s) failed for $AppUrl." }
Write-Host "`nAll page/liveness checks passed: $AppUrl (SQL access and booking are verified separately in steps 3 and 4)." -ForegroundColor Green

if ($Open) {
    $edge = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $edge) { throw 'Microsoft Edge was not found.' }
    Start-Process -FilePath $edge -ArgumentList "--app=$AppUrl/"
    Write-Ok 'Opened in a Microsoft Edge app window'
}
