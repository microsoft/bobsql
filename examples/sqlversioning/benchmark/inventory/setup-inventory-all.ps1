<#
.SYNOPSIS
    Sets up all 4 Inventory Management databases.
.DESCRIPTION
    Creates inventory_baseline, inventory_rcsi, inventory_adr_rcsi, inventory_adr_rcsi_ol
    with 50K products across 20 categories each.
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
$scripts = @(
    @{ Name = "inventory_baseline";    File = "setup-inventory-baseline.sql" },
    @{ Name = "inventory_rcsi";        File = "setup-inventory-rcsi.sql" },
    @{ Name = "inventory_adr_rcsi";    File = "setup-inventory-adr-rcsi.sql" },
    @{ Name = "inventory_adr_rcsi_ol"; File = "setup-inventory-adr-rcsi-ol.sql" }
)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " INVENTORY MANAGEMENT: DATABASE SETUP" -ForegroundColor Green
Write-Host " Server: $ServerName" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green

foreach ($s in $scripts) {
    $path = Join-Path $scriptDir $s.File
    if (-not (Test-Path $path)) {
        Write-Error "Script not found: $path"
        return
    }
    Write-Host ""
    Write-Host "  Creating $($s.Name) ..." -ForegroundColor Yellow
    & $SqlsimPath -S $ServerName -d master -E -i $path
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create $($s.Name) (exit $LASTEXITCODE)"
        return
    }
    Write-Host "  $($s.Name) — done" -ForegroundColor Green
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " All 4 Inventory Management databases created successfully." -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
