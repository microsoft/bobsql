<#
.SYNOPSIS
    Runs the bounded Performance Ward General JSON workload with sqlsim.

.EXAMPLE
    ./run-workload.ps1
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $WorkloadPath = (Join-Path $PSScriptRoot 'workload-8.json'),

    [string] $OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$loadEnv = Join-Path $PSScriptRoot '..\..\first-app\load-env.ps1'
. $loadEnv -Require @('WardGeneral__Server', 'WardGeneral__Database') -Quiet

if ([string]::IsNullOrWhiteSpace($env:SQLSIM)) {
    throw 'Set SQLSIM to the full path of sqlsim.exe from the https://aka.ms/sqlsimtools release.'
}
$sqlsim = $env:SQLSIM
if (-not (Test-Path -LiteralPath $sqlsim -PathType Leaf)) {
    throw "SQLSIM does not point to a file: $sqlsim"
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI was not found. Install it, run az login, and retry.'
}

if (-not $OutputPath) {
    $OutputPath = Join-Path $PSScriptRoot 'results\standalone\sqlsim.txt'
}
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$server = $env:WardGeneral__Server
$database = $env:WardGeneral__Database
$workload = (Resolve-Path -LiteralPath $WorkloadPath).Path
$definition = Get-Content -LiteralPath $workload -Raw | ConvertFrom-Json
$totalThreads = ($definition.workloads | Measure-Object -Property threads -Sum).Sum

Write-Host 'Performance stage 1 workload' -ForegroundColor Cyan
Write-Host ("  Target       {0} @ {1}" -f $database, $server)
Write-Host ("  Definition   {0}" -f $workload)
Write-Host ("  Duration     {0} seconds" -f $definition.duration_seconds)
Write-Host ("  Threads      {0} across {1} procedure groups" -f $totalThreads, $definition.workloads.Count)
Write-Host ("  Output       {0}" -f $OutputPath)

$token = az account get-access-token `
    --resource https://database.windows.net/ `
    --query accessToken `
    --output tsv
if ([string]::IsNullOrWhiteSpace($token)) {
    throw 'Azure CLI returned an empty Azure SQL access token. Run az login and retry.'
}

try {
    Push-Location $PSScriptRoot
    try {
        & $sqlsim `
            -S $server `
            -d $database `
            -T $token `
            -workload $workload `
            -retry 3 `
            -retrydelay 5 `
            -t 60 `
            -q `
            -o $OutputPath
    }
    finally {
        Pop-Location
    }
}
finally {
    $token = $null
}

Write-Host 'Workload complete.' -ForegroundColor Green
