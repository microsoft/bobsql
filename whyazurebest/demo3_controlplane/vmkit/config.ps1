# Runs INSIDE the demo VM. No az CLI, no Azure login, no password.
# Copied to C:\demo alongside sqlsim.exe.
# push-vmkit.ps1 copies this file verbatim, so these must match 00-config.ps1.

$script:ServerFqdn   = 'bwpehyperscale-srv.database.windows.net'
$script:DatabaseName = 'bwpehyperscale'
$script:SqlSim       = 'C:\demo\sqlsim.exe'
$script:DemoQuery    = 'SELECT DB_NAME() AS [Database], SUSER_SNAME() AS [ConnectedAs], CURRENT_TIMESTAMP AS [At]'

function Write-Beat {
    param([string]$Title)
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor Cyan
}

function Show-Command {
    param([string]$Command)
    Write-Host ''
    Write-Host "  $ $Command" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host ''
}

function Assert-Kit {
    if (-not (Test-Path $SqlSim)) {
        throw "sqlsim.exe not found at $SqlSim. Copy the demo kit to C:\demo first."
    }
}
