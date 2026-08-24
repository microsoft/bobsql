<#
.SYNOPSIS
    Phase 1. Provisions the whole demo from the presenter's laptop. az CLI only.

.DESCRIPTION
    Runs steps 1 through 6 in order. Every step is idempotent, so if one fails
    you can fix it and re-run from there:

        .\setup-all.ps1 -From 4

    PHASE 1 (this script, from the laptop) creates the network, the VM, the
    Entra-only logical server, the Hyperscale database, and the client
    prerequisites. It opens ZERO SQL connections.

    PHASE 2 (you, inside the VM over RDP) is the data plane. This script stops
    and tells you exactly what to copy across.

.PARAMETER From
    First step to run. Default 1.

.PARAMETER To
    Last step to run. Default 6.

.NOTES
    Step 2 prompts for the VM local administrator password. Nothing is
    generated, nothing is stored, nothing is echoed.
#>

param(
    [ValidateRange(1, 6)][int]$From = 1,
    [ValidateRange(1, 6)][int]$To = 6
)

. "$PSScriptRoot\00-config.ps1"

# An array, not [ordered]@{1=...}. An OrderedDictionary indexed with an integer
# resolves by POSITION, not by key, which silently runs the wrong step.
$steps = @(
    @{ Number = 1; Name = 'Network, subnets, NSG';        Script = '01-network.ps1' }
    @{ Number = 2; Name = 'Client VM + managed identity'; Script = '02-vm.ps1' }
    @{ Number = 3; Name = 'RDP access from this machine'; Script = 'allow-me.ps1' }
    @{ Number = 4; Name = 'Entra-only server + database'; Script = '03-sql.ps1' }
    @{ Number = 5; Name = 'VM client prerequisites';      Script = '04-vm-prereqs.ps1' }
    @{ Number = 6; Name = 'Pre-flight verification';      Script = '05-verify.ps1' }
)

$started = Get-Date

foreach ($step in $steps) {
    $n = $step.Number
    if ($n -lt $From -or $n -gt $To) { continue }

    Write-Host ''
    Write-Host ('=' * 74) -ForegroundColor Cyan
    Write-Host "  STEP $n of 6  -  $($step.Name)" -ForegroundColor Cyan
    Write-Host ('=' * 74) -ForegroundColor Cyan

    $global:LASTEXITCODE = 0
    & (Join-Path $PSScriptRoot $step.Script)

    if ($n -eq 6 -and $LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Fail 'Pre-flight failed. See the table above.'
        exit 1
    }

    # The handoff. Everything above is control plane; everything below needs
    # the demo kit physically present on the VM. This runs whenever step 5 runs,
    # including '-To 5' — stopping early must not skip the copy instructions.
    if ($n -eq 5) {
        $onVm = Invoke-VmScript "if (Test-Path '$VmSqlSim') { 'PRESENT' } else { 'MISSING' }"
        if ($onVm -notmatch 'PRESENT') {
            Write-Host ''
            Write-Host ('=' * 74) -ForegroundColor Yellow
            Write-Host '  PAUSED  -  copy the demo kit to the VM before step 6' -ForegroundColor Yellow
            Write-Host ('=' * 74) -ForegroundColor Yellow
            Write-Host ''
            Write-Host '  1. Push the three kit scripts from here (no RDP needed):' -ForegroundColor Yellow
            Write-Host '         .\push-vmkit.ps1' -ForegroundColor White
            Write-Host ''
            Write-Host '  2. RDP in:' -ForegroundColor Yellow
            Write-Host "         mstsc `"$RdpFilePath`"" -ForegroundColor White
            Write-Host "     Sign in as '$VmAdminUser' with the password you set in step 2." -ForegroundColor DarkGray
            Write-Host ''
            Write-Host '  3. Copy sqlsim.exe across. It is the only file that needs RDP -' -ForegroundColor Yellow
            Write-Host '     drive redirection is on, so your local drives appear under' -ForegroundColor Yellow
            Write-Host '     This PC in the session:' -ForegroundColor Yellow
            Write-Host ''
            Write-Host "         from  $SqlSimLocal" -ForegroundColor White
            Write-Host "         to    $VmKitDir" -ForegroundColor White
            Write-Host ''
            Write-Host "     $VmKitDir should end up containing exactly:" -ForegroundColor DarkGray
            Write-Host '         sqlsim.exe  config.ps1  query.ps1  dns.ps1' -ForegroundColor DarkGray
            Write-Host ''
            Write-Host '  4. In the VM, confirm it works:' -ForegroundColor Yellow
            Write-Host "         cd $VmKitDir" -ForegroundColor White
            Write-Host '         .\query.ps1' -ForegroundColor White
            Write-Host ''
            Write-Host '  5. Back here, finish setup:' -ForegroundColor Yellow
            Write-Host '         .\setup-all.ps1 -From 6' -ForegroundColor White
            Write-Host ''
            exit 0
        }
        Write-Ok "Demo kit already present at $VmKitDir"
    }
}

$elapsed = (Get-Date) - $started

if ($To -lt 6) {
    Write-Host ''
    Write-Host ('=' * 74) -ForegroundColor Yellow
    Write-Host "  Stopped after step $To by request. Pre-flight has NOT run." -ForegroundColor Yellow
    Write-Host ('=' * 74) -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Finish with:' -ForegroundColor Yellow
    Write-Host '         .\setup-all.ps1 -From 6' -ForegroundColor White
    Write-Host ''
    return
}

Write-Host ''
Write-Host ('=' * 74) -ForegroundColor Green
Write-Host ("  Setup complete in {0:N1} minutes." -f $elapsed.TotalMinutes) -ForegroundColor Green
Write-Host ('=' * 74) -ForegroundColor Green
Write-Host ''
Write-Host '  Run of show:' -ForegroundColor Cyan
Write-Host '    Beat 1   VM      .\query.ps1                    works' -ForegroundColor White
Write-Host '    Beat 2   laptop  .\beat-2-add-privatelink.ps1' -ForegroundColor White
Write-Host '             VM      .\query.ps1                    still works' -ForegroundColor White
Write-Host '    Beat 3   laptop  .\beat-3-lockdown.ps1' -ForegroundColor White
Write-Host '    Beat 4   VM      .\query.ps1 -Expect Fail       blocked' -ForegroundColor White
Write-Host '             VM      .\dns.ps1                      public IP' -ForegroundColor White
Write-Host '    Beat 5   laptop  .\beat-5-dns-link.ps1' -ForegroundColor White
Write-Host '             VM      .\dns.ps1                      10.42.1.x' -ForegroundColor White
Write-Host '             VM      .\query.ps1                    works' -ForegroundColor White
Write-Host ''
Write-Host '  Between rehearsals:  .\reset-demo.ps1  then  .\05-verify.ps1' -ForegroundColor Cyan
Write-Host ''
