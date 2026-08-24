<#
.SYNOPSIS
    Queries the Hyperscale database as the VM's managed identity.

.DESCRIPTION
    Runs INSIDE the demo VM. This is the client half of every beat.

    There is no password and no access token. The VM's system-assigned managed
    identity IS the Microsoft Entra admin of the logical server, so
    -A ActiveDirectoryMsi authenticates as an admin with nothing stored
    anywhere and nothing that expires.

.EXAMPLE
    .\query.ps1
    .\query.ps1 -Expect Fail
#>

param(
    [ValidateSet('Pass', 'Fail')]
    [string]$Expect = 'Pass',

    [int]$LoginTimeout = 30
)

. "$PSScriptRoot\config.ps1"
Assert-Kit

Show-Command "sqlsim -S $ServerFqdn -d $DatabaseName -A ActiveDirectoryMsi -Q `"$DemoQuery`""

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$output = & $SqlSim -S $ServerFqdn -d $DatabaseName -A ActiveDirectoryMsi -Q $DemoQuery -l $LoginTimeout 2>&1 | Out-String
$sw.Stop()

Write-Host $output
Write-Host ("  elapsed {0:N1}s" -f $sw.Elapsed.TotalSeconds) -ForegroundColor DarkGray

$failed = ($LASTEXITCODE -ne 0) -or ($output -match 'Msg \d+|Login failed|Cannot open|error|denied|not accessible')

if ($Expect -eq 'Pass') {
    if ($failed) {
        Write-Host ''
        Write-Host '  FAILED - but this beat expected the query to succeed.' -ForegroundColor Red
        exit 1
    }
    Write-Host ''
    Write-Host '  Connected. The VM can read the database.' -ForegroundColor Green
}
else {
    if (-not $failed) {
        Write-Host ''
        Write-Host '  SUCCEEDED - but this beat expected the query to fail.' -ForegroundColor Red
        exit 1
    }
    Write-Host ''
    Write-Host '  Blocked, as expected. Read the error text above out loud.' -ForegroundColor Green
    Write-Host '  The public endpoint is gone. No firewall rule rejected us -' -ForegroundColor DarkGray
    Write-Host '  every rule is still in place.' -ForegroundColor DarkGray
}
