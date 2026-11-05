<#
.SYNOPSIS
    Measures a lightweight laptop-to-database round trip for contamination checks.

.DESCRIPTION
    Executes SELECT 1 twenty times over one token-authenticated sqlsim connection.
    This is a control signal for network drift, not a bandwidth benchmark.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $OutputPath,

    [ValidateRange(5, 100)]
    [int] $Iterations = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$loadEnv = Join-Path $PSScriptRoot '..\..\first-app\load-env.ps1'
. $loadEnv -Require @('WardGeneral__Server', 'WardGeneral__Database') -Quiet

if ([string]::IsNullOrWhiteSpace($env:SQLSIM) -or
    -not (Test-Path -LiteralPath $env:SQLSIM -PathType Leaf)) {
    throw 'Run preflight.ps1 first so SQLSIM points to sqlsim.exe.'
}

$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$token = az account get-access-token `
    --resource https://database.windows.net/ `
    --query accessToken `
    --output tsv
if ([string]::IsNullOrWhiteSpace($token)) {
    throw 'Azure CLI returned an empty Azure SQL access token.'
}

try {
    $null = & $env:SQLSIM `
        -S $env:WardGeneral__Server `
        -d $env:WardGeneral__Database `
        -T $token `
        -Q 'SET NOCOUNT ON; SELECT 1 AS NetworkControl;' `
        -n 1 `
        -r $Iterations `
        -retry 3 `
        -retrydelay 5 `
        -q `
        -json `
        -v `
        -o $OutputPath
}
finally {
    $token = $null
}

$result = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json
if (-not $result.success -or $result.metrics.errors.total -ne 0) {
    throw "Network control failed. See $OutputPath."
}

[pscustomobject]@{
    AverageQueryMs = [double]$result.metrics.query_execution_operations.avg_elapsed_ms
    AverageConnectMs = [double]$result.metrics.connection_operations.avg_connect_time_ms
    Iterations = $Iterations
    OutputPath = $OutputPath
}
