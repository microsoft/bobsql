<#
.SYNOPSIS
    Stop and remove the Observability wardgeneral_health Extended Events session.

.DESCRIPTION
    Loads the shared Ward General configuration, resolves the new Go-based
    sqlcmd, and runs teardown-xevent-health.sql with passwordless
    authentication. Dropping the session permanently discards its volatile
    ring-buffer contents.

.PARAMETER Server
    Azure SQL logical-server FQDN. Defaults to WardGeneral__Server, including a
    value loaded from first-app/wardgeneral.env when that file exists.

.PARAMETER Database
    Database name. Defaults to WardGeneral__Database, then wardgeneral.

.PARAMETER SqlCmd
    Explicit path to the new sqlcmd executable. Defaults to SQLCMD, standard
    install locations, and the sqlcmd command on PATH.

.EXAMPLE
    ./teardown-xevent-health.ps1 -WhatIf

.EXAMPLE
    ./teardown-xevent-health.ps1
#>
#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string] $Server,
    [string] $Database,
    [string] $SqlCmd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$here = $PSScriptRoot

$loadEnv = Join-Path $here '..' '..' '..' 'first-app' 'load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }

if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') {
    throw 'No server. Fill in WardGeneral__Server in first-app/wardgeneral.env, set the environment variable, or pass -Server <your-server>.database.windows.net.'
}

$isNewSqlcmd = {
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
) | Where-Object { $_ -and (Test-Path $_) -and (& $isNewSqlcmd $_) } |
    Select-Object -First 1

if (-not $sqlcmdPath) {
    throw @'
The new sqlcmd was not found. Install it with:

  winget install --id Microsoft.Sqlcmd

Then open a new PowerShell session, or set SQLCMD to its full path.
'@
}

$queryPath = Join-Path $here 'teardown-xevent-health.sql'
if (-not (Test-Path $queryPath)) { throw "Missing SQL script: $queryPath" }

$target = "wardgeneral_health on $Server/$Database"
if (-not $PSCmdlet.ShouldProcess($target, 'Stop and drop the Extended Events session, discarding its ring buffer')) {
    return
}

Write-Host 'Observability — remove the Ward General health session' -ForegroundColor Cyan
Write-Host "Server   : $Server" -ForegroundColor Gray
Write-Host "Database : $Database" -ForegroundColor Gray
Write-Host "sqlcmd   : $sqlcmdPath" -ForegroundColor Gray
Write-Host ''

& $sqlcmdPath -S $Server -d $Database -G -C -b -i $queryPath
if ($LASTEXITCODE -ne 0) {
    throw "sqlcmd exited with code $LASTEXITCODE."
}