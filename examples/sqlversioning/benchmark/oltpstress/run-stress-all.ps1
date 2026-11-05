<#
.SYNOPSIS
    Runs all 4 OLTP stress workloads sequentially.
.DESCRIPTION
    Pure INSERT/UPDATE/DELETE workload (40 threads, no readers) under 4 configs:
      1. stress_baseline     — no RCSI, no ADR, no OL
      2. stress_rcsi         — RCSI ON
      3. stress_adr_rcsi     — RCSI ON, ADR ON
      4. stress_adr_rcsi_ol  — RCSI ON, ADR ON, OL ON
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
$configs = @(
    @{ Name = "Baseline";        Database = "stress_baseline";    Workload = "workload-baseline.json" },
    @{ Name = "RCSI";            Database = "stress_rcsi";        Workload = "workload-rcsi.json" },
    @{ Name = "ADR + RCSI";      Database = "stress_adr_rcsi";    Workload = "workload-adr-rcsi.json" },
    @{ Name = "ADR + RCSI + OL"; Database = "stress_adr_rcsi_ol"; Workload = "workload-adr-rcsi-ol.json" }
)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " OLTP STRESS: PURE WRITE WORKLOAD (40 threads, no readers)" -ForegroundColor Green
Write-Host " Server: $ServerName" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green

Push-Location $scriptDir

foreach ($c in $configs) {
    $workloadPath = Join-Path $scriptDir $c.Workload
    if (-not (Test-Path $workloadPath)) {
        Pop-Location
        Write-Error "Workload file not found: $workloadPath"
        return
    }
    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "  Config: $($c.Name)  |  Database: $($c.Database)" -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
    & $SqlsimPath -S $ServerName -E -d $c.Database -workload $workloadPath -querystats -q
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        Write-Error "Workload failed for $($c.Name) (exit $LASTEXITCODE)"
        return
    }
    Write-Host "  $($c.Name) — complete" -ForegroundColor Green
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " ALL 4 OLTP STRESS BENCHMARKS COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

Pop-Location
