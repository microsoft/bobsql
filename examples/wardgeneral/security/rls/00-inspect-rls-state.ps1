<#
.SYNOPSIS
    Inspect whether the Security RLS example is in a clean state.

.DESCRIPTION
    Reports recognized Ward General and DAB listeners, the generated _local
    directory, and the number of Security RLS database objects. This script
    is read-only and does not stop processes, remove files, or change SQL.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $Server,
    [string] $Database,
    [string] $SqlCmd,
    [int] $DabPort = 5000,
    [int[]] $AppPorts = @(7170, 5170)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

$loadEnv = Join-Path $here '..' '..' 'first-app' 'load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }
if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') {
    throw 'No server. Fill in WardGeneral__Server in first-app/wardgeneral.env, set the environment variable, or pass -Server explicitly.'
}

$isGoSqlcmd = {
    param([string] $Executable)
    if (-not $Executable) { return $false }
    & $Executable --version 2>&1 | Out-Null
    return $LASTEXITCODE -eq 0
}
$sqlcmdPath = @(
    $SqlCmd,
    $env:SQLCMD,
    (Join-Path $env:LOCALAPPDATA 'Programs\sqlcmd\sqlcmd.exe'),
    'C:\Program Files\SqlCmd\sqlcmd.exe',
    (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
) | Where-Object { $_ -and (Test-Path $_) -and (& $isGoSqlcmd $_) } |
    Select-Object -First 1
if (-not $sqlcmdPath) { throw 'The new Go-based sqlcmd was not found.' }

$appListeners = @(foreach ($port in $AppPorts) {
    Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue |
        Select-Object -First 1
})
$recognizedAppListeners = @($appListeners | Where-Object {
    $process = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
    $process -and $process.ProcessName -in @('WardGeneral.Web', 'dotnet')
})

$dabListener = Get-NetTCPConnection -State Listen -LocalPort $DabPort `
    -ErrorAction SilentlyContinue | Select-Object -First 1
$recognizedDabListener = $null
if ($dabListener) {
    $process = Get-Process -Id $dabListener.OwningProcess -ErrorAction SilentlyContinue
    $commandLine = (Get-CimInstance Win32_Process `
        -Filter "ProcessId=$($dabListener.OwningProcess)" -ErrorAction SilentlyContinue).CommandLine
    if ($process -and ($process.ProcessName -ieq 'dab' -or
        $commandLine -match '(?i)(Microsoft\.DataApiBuilder|\bdab(?:\.exe)?\s+start\b)')) {
        $recognizedDabListener = $dabListener
    }
}

$localExists = Test-Path (Join-Path $here '_local')
$result = @(& $sqlcmdPath -S $Server -d $Database -G -C -b -h -1 -W `
    -i (Join-Path $here '00-verify-clean.sql'))
if ($LASTEXITCODE -ne 0) { throw "Clean-state inspection failed (sqlcmd exit $LASTEXITCODE)." }
$remainingObjects = [int] ([string] ($result | Where-Object { $_ -match '^\s*\d+\s*$' } |
    Select-Object -Last 1)).Trim()

$resetRequired = $recognizedAppListeners.Count -gt 0 -or
    $null -ne $recognizedDabListener -or $localExists -or $remainingObjects -gt 0

Write-Host 'Security RLS state inspection' -ForegroundColor Cyan
Write-Host "  Ward General running: $($recognizedAppListeners.Count -gt 0)"
Write-Host "  Secured DAB running:   $($null -ne $recognizedDabListener)"
Write-Host "  _local exists:         $localExists"
Write-Host "  RLS objects remaining: $remainingObjects"
Write-Output "ResetRequired=$resetRequired"