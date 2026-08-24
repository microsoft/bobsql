<#
.SYNOPSIS
    BEAT 5. Links the private DNS zone to the VNet. The demo comes back to life.

.DESCRIPTION
    Runs from the presenter's LAPTOP. Control plane only.

    One command. --registration-enabled false, because this zone holds a
    private endpoint A record, not VM registrations.

.NOTES
    Learn, on the single most common Private Link failure: "The private DNS
    zone isn't linked to the querying VNet (the most common reason)."

    That is exactly the state Beat 4 showed. The private endpoint existed, the
    zone existed, the A record was correct - and the VM still resolved a public
    IP, because Azure DNS could not consult a zone that was not linked to the
    VNet the query came from.
#>

. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

Write-Beat 'BEAT 5  Link the private DNS zone to the VNet.'

$vnetId = & az network vnet show -g $ResourceGroup -n $VNetName --query id -o tsv 2>&1
if ($LASTEXITCODE -ne 0) { throw "Could not find VNet '$VNetName'.`n$vnetId" }
$vnetId = ($vnetId | Out-String).Trim()

Write-Step "VNet link '$DnsLinkName'"
$link = Invoke-Az @(
    'network', 'private-dns', 'link', 'vnet', 'show',
    '-g', $ResourceGroup, '-z', $PrivateDnsZone, '-n', $DnsLinkName
) -AllowFailure

if ($link) {
    Write-Skip 'Already exists - Beat 4 should have been run before this'
}
else {
    Show-Command "az network private-dns link vnet create -z $PrivateDnsZone -n $DnsLinkName --virtual-network $VNetName --registration-enabled false"
    Invoke-Az @(
        'network', 'private-dns', 'link', 'vnet', 'create',
        '-g', $ResourceGroup,
        '-z', $PrivateDnsZone,
        '-n', $DnsLinkName,
        '--virtual-network', $vnetId,
        '--registration-enabled', 'false'
    ) | Out-Null
    Write-Ok 'Created'
}

Write-Host ''
Write-Host '  Now go to the RDP window and run:  .\dns.ps1' -ForegroundColor Cyan
Write-Host '                            then:  .\query.ps1' -ForegroundColor Cyan
Write-Host ''
Write-Host '  Recap of what we did NOT do to get here:' -ForegroundColor White
Write-Host '    no firewall rule' -ForegroundColor White
Write-Host '    no 0.0.0.0' -ForegroundColor White
Write-Host '    no VPN client' -ForegroundColor White
Write-Host '    no code change' -ForegroundColor White
Write-Host '    no redeploy' -ForegroundColor White
Write-Host '    no new connection string' -ForegroundColor White
Write-Host ''
