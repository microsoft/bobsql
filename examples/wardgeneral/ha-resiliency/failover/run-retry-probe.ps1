<#
.SYNOPSIS
    Run the Ward General retry policy continuously during a failover test.

.DESCRIPTION
    Loads the Ward General App configuration and starts a finite .NET console probe.
    The probe references WardGeneral.Data and uses its existing RetryPolicy on
    both connection open and an idempotent read. This script changes nothing in
    Azure and does not trigger the failover.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $Server,
    [string] $Database,
    [ValidateRange(100, 60000)]
    [int] $IntervalMs = 1000,
    [ValidateRange(10, 3600)]
    [int] $DurationSeconds = 120,
    [string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$loadEnv = Join-Path $PSScriptRoot '..' '..' 'first-app' 'load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }

if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') {
    throw 'No server. Fill in WardGeneral__Server in first-app/wardgeneral.env, set the environment variable, or pass -Server explicitly.'
}

if (-not $OutputDirectory) {
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) "wardgeneral-ha-resiliency-probe-$stamp"
}
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$OutputDirectory = (Resolve-Path $OutputDirectory).Path
$probeOutput = Join-Path $OutputDirectory 'probe-output.txt'

Write-Host "ProbeEvidence=$probeOutput"

$project = Join-Path $PSScriptRoot 'retry-probe' 'RetryProbe.csproj'
dotnet run --project $project --configuration Release --no-launch-profile -- `
    $Server $Database $IntervalMs $DurationSeconds 2>&1 |
    Tee-Object -FilePath $probeOutput
if ($LASTEXITCODE -ne 0) {
    throw "The retry probe reported one or more requests that failed after all retries (exit code $LASTEXITCODE)."
}
