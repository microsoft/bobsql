[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$pidPath = Join-Path $PSScriptRoot '.run\app.pid'
$process = $null
if (Test-Path $pidPath) {
    $processId = [int](Get-Content -Raw $pidPath)
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($process) {
        & taskkill.exe /PID $processId /T /F *> $null
        Write-Host "Stopped local Caldova app process tree $processId." -ForegroundColor Green
    }
    Remove-Item $pidPath -Force
}
$listener = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
    & taskkill.exe /PID $listener.OwningProcess /T /F *> $null
    Write-Host "Stopped remaining port 8000 process tree $($listener.OwningProcess)." -ForegroundColor Green
}
if (-not $process -and -not $listener) { Write-Host 'No local Caldova app process is running.' }
