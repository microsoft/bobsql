#requires -Version 7.0
<#
    Ward General — "Scale it" demo: drive a READ-ONLY load surge with sqlsim.

    Runs a mix of the app's real read paths against the PRIMARY compute to justify
    pulling the compute slider:
      * read-census-board.sql  — ops.vBedCensus (the Home board)     x20 threads
      * read-patient-chart.sql — clinical.GetPatientChart (bedside)  x12 threads
      * read-worklist.sql      — clinical.SearchEncounters (worklist) x6 threads

    READ-ONLY BY DESIGN: every batch is a SELECT or a read stored procedure —
    it never inserts, updates, or deletes. Safe to run against the live demo DB.

    It intentionally does NOT set ApplicationIntent=ReadOnly — the goal is to load
    the PRIMARY's compute (so scaling vCores is the answer). To instead prove read
    scale-out isolation on a replica, that's the "Modernize it" Research page.

    Passwordless: acquires an Entra token via `az account get-access-token`.
    Requires `az login`.

    Usage:
      ./Run-ReadSurge.ps1                      # 60s surge (from read-surge.json)
      ./Run-ReadSurge.ps1 -DurationSeconds 120 # longer surge
      ./Run-ReadSurge.ps1 -Report              # also build+open an HTML perf report
      ./Run-ReadSurge.ps1 -Server <srv> -Database <db>
#>
[CmdletBinding()]
param(
    [string]$Server   = 'collierhealth-17.database.windows.net',
    [string]$Database  = 'wardgeneral',
    [int]   $DurationSeconds,
    [string]$SqlSim   = (Join-Path $PSScriptRoot '..' 'sqlsim.exe'),
    [string]$Workload = (Join-Path $PSScriptRoot 'read-surge.json'),
    [switch]$Report
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $SqlSim))   { throw "sqlsim not found: $SqlSim" }
if (-not (Test-Path $Workload)) { throw "workload not found: $Workload" }

Write-Host "Acquiring Entra token (az)..." -ForegroundColor Cyan
$token = az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv
if ([string]::IsNullOrWhiteSpace($token)) { throw "Failed to get an Entra token — run 'az login' first." }

# Run from this folder so the workload's relative .sql paths resolve.
Push-Location $PSScriptRoot
try {
    $runJson = $Workload
    if ($PSBoundParameters.ContainsKey('DurationSeconds')) {
        # Override the duration without touching the checked-in workload file.
        $wl = Get-Content $Workload -Raw | ConvertFrom-Json
        $wl.duration_seconds = $DurationSeconds
        $runJson = Join-Path $PSScriptRoot '.read-surge.run.json'
        $wl | ConvertTo-Json -Depth 5 | Set-Content $runJson -Encoding UTF8
    }

    $secs = if ($PSBoundParameters.ContainsKey('DurationSeconds')) { $DurationSeconds } else { 60 }
    Write-Host "Driving READ-ONLY surge at $Database on $Server for ~${secs}s..." -ForegroundColor Cyan
    Write-Host "  (Ctrl+C to stop early. Watch CPU on the primary, then pull the compute slider.)" -ForegroundColor DarkGray

    $simArgs = @('-S', $Server, '-d', $Database, '-T', $token, '-N', 's', '-workload', $runJson, '-querystats')
    $jsonOut = $null
    if ($Report) {
        $stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
        $jsonOut = Join-Path $PSScriptRoot "read-surge-$stamp.json"
        $simArgs += @('-json', '-q', '-o', $jsonOut)   # capture a machine-readable querystats report
    }

    & $SqlSim @simArgs

    if ($Report -and $jsonOut -and (Test-Path $jsonOut)) {
        # Build + open the interactive HTML performance report from the querystats JSON.
        $chart = Join-Path $PSScriptRoot '..' 'reports' 'querystats-chart.ps1'
        if (Test-Path $chart) {
            $htmlOut = [System.IO.Path]::ChangeExtension($jsonOut, 'html')
            & $chart -JsonFile $jsonOut -OutputFile $htmlOut
            Write-Host "Performance report: $htmlOut" -ForegroundColor Green
        }
        else {
            Write-Warning "Report script not found: $chart (querystats JSON captured at $jsonOut)"
        }
    }
}
finally {
    Remove-Item (Join-Path $PSScriptRoot '.read-surge.run.json') -ErrorAction SilentlyContinue
    Pop-Location
}
