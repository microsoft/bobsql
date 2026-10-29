<#
.SYNOPSIS
    Verifies every prerequisite for the Performance Stage 1 workload.

.DESCRIPTION
    If SQLSIM is absent or invalid, prompts for the full local path to
    sqlsim.exe and sets SQLSIM for the current process. No secret is requested.
    The script then proves ODBC 18, Azure CLI authentication, control-plane
    access, token-auth data-plane connectivity through the firewall, the Ward
    General procedure/data contract, Query Store, and the HS_Gen5_8 start.

    -ResetDemoData previews exact WG-PERF-SCALE rows. Add -ApproveCleanup to
    perform the atomic reset. Cleanup is never automatic.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $ResourceGroup = $env:RG,

    [switch] $ResetDemoData,

    [switch] $ApproveCleanup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

function Resolve-SqlsimPath {
    $candidate = $env:SQLSIM

    if (-not [string]::IsNullOrWhiteSpace($candidate) -and
        (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $candidate).Path
    }

    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        Write-Warning "SQLSIM is set but does not point to a file: $candidate"
    }

    Write-Host ''
    Write-Host 'Download and extract sqlsim from https://aka.ms/sqlsimtools.' -ForegroundColor Yellow
    $candidate = Read-Host 'Enter the full path to sqlsim.exe'
    $candidate = $candidate.Trim().Trim('"')

    if ([string]::IsNullOrWhiteSpace($candidate) -or
        -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "sqlsim.exe was not found at '$candidate'. No Azure change was made."
    }
    if ([System.IO.Path]::GetFileName($candidate) -ine 'sqlsim.exe') {
        throw "Expected a path ending in sqlsim.exe; received '$candidate'."
    }

    $resolved = (Resolve-Path -LiteralPath $candidate).Path
    $env:SQLSIM = $resolved
    Write-Host 'Set SQLSIM for the current PowerShell process.' -ForegroundColor Green
    return $resolved
}

if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    throw 'Set RG or pass -ResourceGroup.'
}
if ($ApproveCleanup -and -not $ResetDemoData) {
    throw '-ApproveCleanup requires -ResetDemoData.'
}

$loadEnv = Join-Path $PSScriptRoot '..\..\first-app\load-env.ps1'
. $loadEnv -Require @('WardGeneral__Server', 'WardGeneral__Database') -Quiet

$sqlsim = Resolve-SqlsimPath

$odbc18 = Get-OdbcDriver -Name 'ODBC Driver 18 for SQL Server' -ErrorAction SilentlyContinue
if (-not $odbc18) {
    throw 'ODBC Driver 18 for SQL Server is not installed.'
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI was not found. Install it, run az login, and retry.'
}

$account = az account show --query '{name:name,user:user.name,tenantId:tenantId}' --output json |
    ConvertFrom-Json
if (-not $account) {
    throw 'No active Azure CLI account was found. Run az login and retry.'
}

$serverFqdn = $env:WardGeneral__Server
$serverName = $serverFqdn.Split('.')[0]
$database = $env:WardGeneral__Database

$resource = az sql db show `
    --resource-group $ResourceGroup `
    --server $serverName `
    --name $database `
    --query '{edition:edition,status:status,serviceObjective:currentServiceObjectiveName}' `
    --output json | ConvertFrom-Json

if ($resource.edition -ne 'Hyperscale') {
    throw "Expected Hyperscale; Azure reports '$($resource.edition)'."
}
if ($resource.status -ne 'Online') {
    throw "Expected an Online database; Azure reports '$($resource.status)'."
}
if ($resource.serviceObjective -ne 'HS_Gen5_8') {
    throw "Stage 1 must begin at HS_Gen5_8; Azure reports '$($resource.serviceObjective)'."
}

$token = az account get-access-token `
    --resource https://database.windows.net/ `
    --query accessToken `
    --output tsv
if ([string]::IsNullOrWhiteSpace($token)) {
    throw 'Azure CLI returned an empty Azure SQL access token. Run az login and retry.'
}

$outputDirectory = Join-Path $PSScriptRoot 'results\preflight'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$outputPath = Join-Path $outputDirectory 'preflight.txt'
$preflightSql = Join-Path $PSScriptRoot 'preflight.sql'

try {
    if ($ResetDemoData) {
        $cleanupSql = if ($ApproveCleanup) {
            Join-Path $PSScriptRoot 'cleanup-apply.sql'
        }
        else {
            Join-Path $PSScriptRoot 'cleanup-preview.sql'
        }
        $cleanupOutput = Join-Path $outputDirectory $(if ($ApproveCleanup) {
            'cleanup-apply.txt'
        }
        else {
            'cleanup-preview.txt'
        })

        & $sqlsim `
            -S $serverFqdn `
            -d $database `
            -T $token `
            -i $cleanupSql `
            -t 120 `
            -stoponerror `
            -o $cleanupOutput

        if ($ApproveCleanup) {
            Write-Host "Demo 1 cleanup applied. Evidence: $cleanupOutput" -ForegroundColor Green
        }
        else {
            Write-Host "Cleanup preview only. Evidence: $cleanupOutput" -ForegroundColor Yellow
            Write-Host 'Re-run with -ResetDemoData -ApproveCleanup to delete those exact rows.' -ForegroundColor Yellow
        }
    }

    & $sqlsim `
        -S $serverFqdn `
        -d $database `
        -T $token `
        -i $preflightSql `
        -retry 3 `
        -retrydelay 5 `
        -t 30 `
        -stoponerror `
        -o $outputPath
}
finally {
    $token = $null
}

Write-Host ''
Write-Host 'Stage 1 preflight passed.' -ForegroundColor Green
Write-Host ("  sqlsim       {0}" -f $sqlsim)
Write-Host ("  ODBC         {0}" -f $odbc18.Name)
Write-Host ("  Azure account {0}" -f $account.user)
Write-Host ("  Database     {0} @ {1}" -f $database, $serverFqdn)
Write-Host ("  SLO          {0}" -f $resource.serviceObjective)
Write-Host ("  Evidence     {0}" -f $outputPath)
Write-Host 'Token authentication and the current firewall/network path are working.' -ForegroundColor Green
