<#
.SYNOPSIS
    Runs all 4 Inventory Management workloads sequentially and saves results.
.DESCRIPTION
    Reader-writer contention workload (40 threads: 15 writers + 25 readers, 30s) under 4 configs:
      1. inventory_baseline     — no RCSI, no ADR, no OL (readers blocked by writers)
      2. inventory_rcsi         — RCSI ON (readers use row versions, no blocking)
      3. inventory_adr_rcsi     — RCSI ON, ADR ON (versions in PVS instead of tempdb)
      4. inventory_adr_rcsi_ol  — RCSI ON, ADR ON, OL ON (optimized lock memory)
.PARAMETER ServerName
    SQL Server instance name. Default: localhost.
.PARAMETER SqlsimPath
    Path to sqlsim.exe.
#>
[CmdletBinding()]
param(
    [string]$ServerName = "localhost",
    [string]$SqlsimPath = "C:\bwsql\sqlsimtools\sqlsim\build\x64\Release\sqlsim.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path $SqlsimPath)) {
    Write-Error "sqlsim.exe not found at '$SqlsimPath'. Specify -SqlsimPath."
    return
}

$scriptDir = $PSScriptRoot
$resultsDir = Join-Path $scriptDir "results"
if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outputFile = Join-Path $resultsDir "inventory-$timestamp.txt"

$configs = @(
    @{ Name = "Baseline";        Database = "inventory_baseline" },
    @{ Name = "RCSI";            Database = "inventory_rcsi" },
    @{ Name = "ADR + RCSI";      Database = "inventory_adr_rcsi" },
    @{ Name = "ADR + RCSI + OL"; Database = "inventory_adr_rcsi_ol" }
)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " INVENTORY MANAGEMENT: READER-WRITER CONTENTION BENCHMARK" -ForegroundColor Green
Write-Host " Server: $ServerName" -ForegroundColor Green
Write-Host " 40 threads (15 writers + 25 readers), 30 seconds each" -ForegroundColor Green
Write-Host " Results: $outputFile" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green

Push-Location $scriptDir

$workloadPath = Join-Path $scriptDir "workload-baseline.json"
if (-not (Test-Path $workloadPath)) {
    Pop-Location
    Write-Error "Workload file not found: $workloadPath"
    return
}

# Truncate output file
"" | Set-Content $outputFile

foreach ($c in $configs) {
    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "  Config: $($c.Name)  |  Database: $($c.Database)" -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------" -ForegroundColor Cyan

    "===== $($c.Name) ($($c.Database)) =====" | Add-Content $outputFile

    & $SqlsimPath -S $ServerName -E -d $c.Database -workload $workloadPath -querystats -q 2>&1 | Tee-Object -Append -FilePath $outputFile
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  $($c.Name) — completed with errors (deadlocks expected on baseline)" -ForegroundColor DarkYellow
    } else {
        Write-Host "  $($c.Name) — complete" -ForegroundColor Green
    }
    "" | Add-Content $outputFile
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " ALL 4 INVENTORY BENCHMARKS COMPLETE" -ForegroundColor Green
Write-Host " Results saved: $outputFile" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

Pop-Location
