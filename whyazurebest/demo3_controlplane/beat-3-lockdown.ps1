<#
.SYNOPSIS
    BEAT 3. Turns off the public endpoint. One property. One REST call.

.DESCRIPTION
    Runs from the presenter's LAPTOP. Control plane only.

    Sets publicNetworkAccess = Disabled on the logical server. Learn: "When
    Public network access is set to Disable, only connections from private
    endpoints are allowed."

    Note what this does NOT do. It does not delete a firewall rule. It does not
    touch the 0.0.0.0 "Allow Azure services" rule, which is still sitting there
    and is about to be shown to be worthless.

.PARAMETER ShowRest
    Echoes the underlying ARM REST call so the audience sees that a network
    perimeter change is a single PUT against management.azure.com.

.NOTES
    ORDERING IS LOAD-BEARING. Learn: "When Public network access is set to
    Disable, any attempts to add, remove, or edit any firewall rules will be
    denied" (Error 42101). That is why reset-demo.ps1 re-enables public access
    before it touches anything else.
#>

param([switch]$ShowRest)

. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

Write-Beat 'BEAT 3  Disable the public endpoint.'

Write-Step 'Firewall rules that still exist on this server'
$rules = Invoke-Az @('sql', 'server', 'firewall-rule', 'list', '-g', $ResourceGroup, '-s', $ServerName)
foreach ($r in $rules) {
    Write-Ok "$($r.name)  $($r.startIpAddress) - $($r.endIpAddress)"
}
Write-Warn 'We are about to leave every one of these in place.'

Show-Command "az sql server update -g $ResourceGroup -n $ServerName --set publicNetworkAccess=Disabled"

if ($ShowRest) {
    Write-Step 'Underlying ARM call'
    & az sql server update -g $ResourceGroup -n $ServerName `
        --set publicNetworkAccess=Disabled --debug 2>&1 |
        Select-String -Pattern "Request URL|'PUT'|management\.azure\.com" |
        Select-Object -First 6 |
        ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    if ($LASTEXITCODE -ne 0) { throw "az sql server update failed with exit code $LASTEXITCODE" }
}
else {
    Invoke-Az @(
        'sql', 'server', 'update',
        '-g', $ResourceGroup,
        '-n', $ServerName,
        '--set', 'publicNetworkAccess=Disabled'
    ) | Out-Null
}

Write-Step 'Confirming'
$state = & az sql server show -g $ResourceGroup -n $ServerName --query publicNetworkAccess -o tsv 2>&1
$state = ($state | Out-String).Trim()
if ($state -ne 'Disabled') { throw "Expected Disabled but found '$state'." }
Write-Ok 'publicNetworkAccess = Disabled'

Write-Host ''
Write-Host '  Note we never deleted a firewall rule.' -ForegroundColor White
Write-Host ''
Write-Host '  Now go to the RDP window and run:  .\query.ps1 -Expect Fail' -ForegroundColor Cyan
Write-Host '                            then:  .\dns.ps1' -ForegroundColor Cyan
Write-Host ''
