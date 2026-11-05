<#
.SYNOPSIS
    Query Azure SQL connection history from the logical server's master database.

.DESCRIPTION
    Loads the shared Ward General server configuration, resolves the new
    Go-based sqlcmd, applies the requested limits to connection-history.sql,
    connects explicitly to master, and returns two result sets: detailed
    sys.event_log rows and five-minute sys.database_connection_stats rows.
    Results include every database visible to the caller on the logical server;
    no database-name filter is applied.

.PARAMETER Hours
    UTC lookback in hours. Defaults to 24 and cannot exceed the documented
    maximum retention period of 30 days.

.PARAMETER EventLimit
    Maximum detailed sys.event_log rows returned. Defaults to 200.

.PARAMETER Server
    Azure SQL logical-server FQDN. Defaults to WardGeneral__Server, including a
    value loaded from first-app/wardgeneral.env.

.PARAMETER SqlCmd
    Explicit path to the new sqlcmd executable. Defaults to SQLCMD, standard
    install locations, and the sqlcmd command on PATH.

.EXAMPLE
    ./run-connection-history.ps1

.EXAMPLE
    ./run-connection-history.ps1 -Hours 72 -EventLimit 500
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateRange(1, 720)]
    [int] $Hours = 24,
    [ValidateRange(1, 5000)]
    [int] $EventLimit = 200,
    [string] $Server,
    [string] $SqlCmd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$here = $PSScriptRoot

$loadEnv = Join-Path $here '..' '..' '..' 'first-app' 'load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }

if (-not $Server) { $Server = $env:WardGeneral__Server }
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

$queryPath = Join-Path $here 'connection-history.sql'
if (-not (Test-Path $queryPath)) { throw "Missing SQL script: $queryPath" }

$executionQueryPath = $queryPath
$temporaryQueryPath = $null
$query = Get-Content -LiteralPath $queryPath -Raw
$hoursDeclaration = 'DECLARE @Hours int = 24;'
$eventLimitDeclaration = 'DECLARE @EventLimit int = 200;'
if (-not $query.Contains($hoursDeclaration) -or
    -not $query.Contains($eventLimitDeclaration)) {
    throw 'connection-history.sql does not contain the expected default declarations.'
}

if ($Hours -ne 24 -or $EventLimit -ne 200) {
    $query = $query.Replace($hoursDeclaration, "DECLARE @Hours int = $Hours;")
    $query = $query.Replace($eventLimitDeclaration, "DECLARE @EventLimit int = $EventLimit;")
    $temporaryQueryPath = Join-Path ([IO.Path]::GetTempPath()) (
        'wardgeneral-connection-history-{0}.sql' -f [guid]::NewGuid()
    )
    [IO.File]::WriteAllText(
        $temporaryQueryPath,
        $query,
        [Text.UTF8Encoding]::new($false)
    )
    $executionQueryPath = $temporaryQueryPath
}

Write-Host 'Observability — logical-server connection history' -ForegroundColor Cyan
Write-Host "Server      : $Server" -ForegroundColor Gray
Write-Host 'Database    : master' -ForegroundColor Gray
Write-Host "UTC lookback: $Hours hour(s)" -ForegroundColor Gray
Write-Host "Event limit : $EventLimit" -ForegroundColor Gray
Write-Host "sqlcmd      : $sqlcmdPath" -ForegroundColor Gray
Write-Host ''

try {
    & $sqlcmdPath -S $Server -d master -G -C -b -i $executionQueryPath
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd exited with code $LASTEXITCODE."
    }
}
finally {
    if ($temporaryQueryPath -and (Test-Path $temporaryQueryPath)) {
        Remove-Item -LiteralPath $temporaryQueryPath -Force
    }
}