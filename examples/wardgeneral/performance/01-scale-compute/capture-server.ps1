<#
.SYNOPSIS
    Captures the Stage 1 server-side evidence with token authentication.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $OutputPath
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
    & $env:SQLSIM `
        -S $env:WardGeneral__Server `
        -d $env:WardGeneral__Database `
        -T $token `
        -i (Join-Path $PSScriptRoot 'measure.sql') `
        -retry 3 `
        -retrydelay 5 `
        -o $OutputPath
}
finally {
    $token = $null
}
