#requires -Version 7.0
<#
    Ward General — stop the running demo (web app + Data API Builder).

    Frees the demo ports (7170 / 5170 app, 5000 DAB) and stops any leftover
    `dab` process and the browser-opener job. Safe to run anytime; local only —
    it does NOT touch Azure or the database.

    Usage:  ./shutdown.ps1
#>
[CmdletBinding()]
param(
    [int[]]$Ports = @(7170, 5170, 5000)
)

$ErrorActionPreference = 'SilentlyContinue'
$stopped = 0

# Stop whatever is listening on the demo ports (the app host + DAB).
foreach ($port in $Ports) {
    $conns = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue
    foreach ($c in $conns) {
        $procId = $c.OwningProcess
        if ($procId -and $procId -gt 0) {
            $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
            if ($p) {
                Write-Host "Stopping $($p.ProcessName) (pid $procId) on port $port ..." -ForegroundColor DarkGray
                Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
                $stopped++
            }
        }
    }
}

# Backstop: any stray DAB process, and the browser-opener job.
Get-Process dab -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "Stopping dab (pid $($_.Id)) ..." -ForegroundColor DarkGray
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    $stopped++
}
Get-Job -Name 'wardgeneral-open-browser' -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue

if ($stopped -gt 0) {
    Write-Host "Shutdown complete ($stopped process(es) stopped)." -ForegroundColor Green
}
else {
    Write-Host "Nothing was running on the demo ports." -ForegroundColor Yellow
}
