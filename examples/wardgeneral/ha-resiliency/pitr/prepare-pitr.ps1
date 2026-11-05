<#
.SYNOPSIS
    Capture the current source-database UTC time for a PITR test copy.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $Server,
    [string] $Database,
    [string] $SqlCmd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$loadEnv = Join-Path $PSScriptRoot '..' '..' 'first-app' 'load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }

if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') {
    throw 'No server. Fill in WardGeneral__Server in first-app/wardgeneral.env, set the environment variable, or pass -Server explicitly.'
}

$sqlcmdPath = @(
    $SqlCmd,
    $env:SQLCMD,
    (Join-Path $env:LOCALAPPDATA 'Programs\sqlcmd\sqlcmd.exe'),
    'C:\Program Files\SqlCmd\sqlcmd.exe',
    (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $sqlcmdPath) { throw 'The new sqlcmd was not found. Install it with: winget install --id Microsoft.Sqlcmd' }

$script = Join-Path $PSScriptRoot 'prepare-recovery-point.sql'
$output = & $sqlcmdPath `
    -S $Server `
    -d $Database `
    --authentication-method ActiveDirectoryDefault `
    -b `
    -h -1 `
    -W `
    -i $script
if ($LASTEXITCODE -ne 0) { throw "PITR preparation failed with exit code $LASTEXITCODE." }
$output | Write-Host

$restoreLine = @($output | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^RestorePointUtc=' })
if ($restoreLine.Count -ne 1) { throw 'The SQL output did not contain exactly one RestorePointUtc value.' }
$restorePoint = $restoreLine[0].Substring('RestorePointUtc='.Length)

Write-Host ''
Write-Host "RestorePointUtc=$restorePoint"
