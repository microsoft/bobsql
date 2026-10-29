#requires -Version 7.0
<#
    Ward General Hospital Digital Chart Application
    shutdown.ps1 : stop the locally running web app and free its ports.

    run.ps1 runs the app in the foreground, so Ctrl+C is the normal way to stop
    it. This script is the backstop for when the terminal was closed instead and
    the process is still holding 7170 / 5170.

    It only stops a process whose name is in -ProcessNames (the app host, or the
    `dotnet` that launched it). Anything else listening on those ports is
    reported and left alone — a port number is not proof of identity.

    Local only; it does NOT touch Azure or the database. -WhatIf for a dry run.

    Runs on Windows, macOS and Linux. Finding which process owns a port is the
    one per-OS step: Get-NetTCPConnection on Windows, lsof elsewhere. Written
    for all three, tested on Windows.

    Usage:  ./shutdown.ps1
            ./shutdown.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [int[]]$Ports = @(7170, 5170, 5000),
    [string[]]$ProcessNames = @('WardGeneral.Web', 'dotnet', 'dab')
)

# Returns the process IDs listening on a port, or nothing.
function Get-PortOwnerId([int]$Port) {
    if ($IsWindows) {
        Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
            ForEach-Object { $_.OwningProcess }
        return
    }

    if (-not (Get-Command lsof -ErrorAction SilentlyContinue)) {
        Write-Warning "lsof not found, so port $Port cannot be checked. Stop the app with Ctrl+C in the window running run.ps1."
        return
    }
    # -t prints bare PIDs, which is all this script needs.
    & lsof -nP -t -iTCP:$Port -sTCP:LISTEN 2>$null | ForEach-Object { [int]$_ }
}

$stopped = 0
$skipped = 0
$planned = 0

foreach ($port in $Ports) {
    # IPv4 and IPv6 listeners report the same owner, so collapse duplicates.
    foreach ($procId in (Get-PortOwnerId $port | Sort-Object -Unique)) {
        if (-not $procId -or $procId -le 0) { continue }

        $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
        if (-not $p) { continue }

        if ($ProcessNames -notcontains $p.ProcessName) {
            Write-Warning "Port $port is held by '$($p.ProcessName)' (pid $procId), which is not the Ward General app. Leaving it alone."
            $skipped++
            continue
        }

        if ($PSCmdlet.ShouldProcess("$($p.ProcessName) (pid $procId) on port $port", 'Stop-Process')) {
            Write-Host "Stopping $($p.ProcessName) (pid $procId) on port $port ..." -ForegroundColor DarkGray
            Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
            $stopped++
        }
        elseif ($WhatIfPreference) {
            $planned++
        }
    }
}

# The browser-opener job run.ps1 starts, if it outlived the app.
Get-Job -Name 'wardgeneral-open-browser' -ErrorAction SilentlyContinue |
    Remove-Job -Force -ErrorAction SilentlyContinue

if ($stopped -gt 0) {
    Write-Host "Shutdown complete ($stopped process(es) stopped)." -ForegroundColor Green
}
elseif ($planned -gt 0) {
    Write-Host "Dry run complete ($planned process(es) would be stopped)." -ForegroundColor Yellow
}
elseif ($skipped -gt 0) {
    Write-Host "Nothing stopped. $skipped port(s) are in use by something else." -ForegroundColor Yellow
}
else {
    Write-Host "The Ward General app is not running." -ForegroundColor Yellow
}
