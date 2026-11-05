<#
.SYNOPSIS
    Stop Ward General and its local DAB endpoint when they are running.

.DESCRIPTION
    Reuses the Ward General shutdown script, then inspects the owner of the DAB
    port. It stops only a process whose executable or command line identifies
    Data API Builder; any unrelated listener is reported and left alone.
#>
#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([int] $DabPort = 5000)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$appShutdown = Join-Path $here '..' '..' 'first-app' 'shutdown.ps1'
& $appShutdown -WhatIf:$WhatIfPreference

$connection = Get-NetTCPConnection -State Listen -LocalPort $DabPort -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $connection) {
    Write-Host 'The DAB endpoint is not running.' -ForegroundColor Yellow
    return
}

$process = Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue
$commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($connection.OwningProcess)" `
    -ErrorAction SilentlyContinue).CommandLine
$isDab = $process.ProcessName -ieq 'dab' -or
    $commandLine -match '(?i)(Microsoft\.DataApiBuilder|\bdab(?:\.exe)?\s+start\b)'
if (-not $isDab) {
    throw "Port $DabPort is held by '$($process.ProcessName)' (PID $($connection.OwningProcess)), not a recognized DAB process. It was left running."
}

if ($PSCmdlet.ShouldProcess(
    "$($process.ProcessName) (PID $($connection.OwningProcess)) on port $DabPort",
    'Stop Data API Builder'
)) {
    Stop-Process -Id $connection.OwningProcess -Force
    Write-Host 'DAB stopped.' -ForegroundColor Green
}
