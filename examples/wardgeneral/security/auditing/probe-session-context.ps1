<#
.SYNOPSIS
    Submit and verify a parameterized SESSION_CONTEXT batch without running Ward General.

.DESCRIPTION
    Runs a finite .NET console probe using the same Microsoft.Data.SqlClient
    version and Entra authentication mode as Ward General. The probe sets unique
    sentinel values, reads them back on the same connection, and prints the
    exact UTC interval and SQL session ID for audit correlation. It does not
    read or change Ward General data or schema.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $Server,
    [string] $Database
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

$project = Join-Path $here 'session-context-probe' 'SessionContextProbe.csproj'
dotnet run --project $project --configuration Release -- $Server $Database
if ($LASTEXITCODE -ne 0) {
    throw "The session-context probe failed with exit code $LASTEXITCODE."
}