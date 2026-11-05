<#
.SYNOPSIS
    Install the Ward General Row-Level Security policy.

.DESCRIPTION
    Loads the Ward General App server and database configuration, resolves the new
    Go-based sqlcmd, and runs row-level-security.sql with Microsoft Entra
    authentication. Restart the app separately with -Enable RowLevelSecurity.
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
$here = $PSScriptRoot

$loadEnv = Join-Path $here '..' '..' 'first-app' 'load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }

if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') {
    throw 'No server. Fill in WardGeneral__Server in first-app/wardgeneral.env, set the environment variable, or pass -Server explicitly.'
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

$queryPath = Join-Path $here 'row-level-security.sql'
Write-Host 'Security — install Ward General Row-Level Security' -ForegroundColor Cyan
Write-Host "Server   : $Server" -ForegroundColor Gray
Write-Host "Database : $Database" -ForegroundColor Gray
Write-Host ''

& $sqlcmdPath -S $Server -d $Database -G -C -b -i $queryPath
if ($LASTEXITCODE -ne 0) { throw "sqlcmd exited with code $LASTEXITCODE." }

Write-Host ''
Write-Host 'RLS is installed. Restart Ward General with:' -ForegroundColor Green
Write-Host '  ./first-app/restart.ps1 -Enable RowLevelSecurity'
