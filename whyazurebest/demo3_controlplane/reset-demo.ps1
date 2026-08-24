<#
.SYNOPSIS
    Rewinds the demo to its Beat 1 state. Run between rehearsals and before the talk.

.DESCRIPTION
    Runs from the presenter's laptop. Undoes Beats 2, 3, and 5 without
    touching the VM, the server, or the database.

.NOTES
    THE ORDER IS LOAD-BEARING.

    Public network access is re-enabled FIRST. Learn: "When Public network
    access is set to Disable, any attempts to add, remove, or edit any firewall
    rules will be denied" - Error 42101. If you try to fix the firewall rule
    before re-enabling public access, it fails.

    The RDP rule is refreshed LAST-ish, because a different venue means a
    different egress IP. That is why this script re-runs allow-me.ps1 rather
    than assuming yesterday's address still works.
#>

. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

Write-Step '1. Re-enabling public network access (must come first - Error 42101)'
Invoke-Az @(
    'sql', 'server', 'update',
    '-g', $ResourceGroup, '-n', $ServerName,
    '--set', 'publicNetworkAccess=Enabled'
) -AllowFailure | Out-Null
$state = (& az sql server show -g $ResourceGroup -n $ServerName --query publicNetworkAccess -o tsv 2>&1 | Out-String).Trim()
Write-Ok "publicNetworkAccess = $state"

Write-Step "2. Deleting private endpoint '$PeName'"
$pe = Invoke-Az @('network', 'private-endpoint', 'show', '-g', $ResourceGroup, '-n', $PeName) -AllowFailure
if ($pe) {
    Invoke-Az @('network', 'private-endpoint', 'delete', '-g', $ResourceGroup, '-n', $PeName) -AllowFailure | Out-Null
    Write-Ok 'Deleted'
}
else {
    Write-Skip 'Already absent'
}

Write-Step "3. Deleting DNS VNet link '$DnsLinkName'"
$link = Invoke-Az @(
    'network', 'private-dns', 'link', 'vnet', 'show',
    '-g', $ResourceGroup, '-z', $PrivateDnsZone, '-n', $DnsLinkName
) -AllowFailure
if ($link) {
    Invoke-Az @(
        'network', 'private-dns', 'link', 'vnet', 'delete',
        '-g', $ResourceGroup, '-z', $PrivateDnsZone, '-n', $DnsLinkName, '--yes'
    ) -AllowFailure | Out-Null
    Write-Ok 'Deleted'
}
else {
    Write-Skip 'Already absent'
}

Write-Step "4. Deleting private DNS zone '$PrivateDnsZone'"
$zone = Invoke-Az @('network', 'private-dns', 'zone', 'show', '-g', $ResourceGroup, '-n', $PrivateDnsZone) -AllowFailure
if ($zone) {
    Invoke-Az @('network', 'private-dns', 'zone', 'delete', '-g', $ResourceGroup, '-n', $PrivateDnsZone, '--yes') -AllowFailure | Out-Null
    Write-Ok 'Deleted'
}
else {
    Write-Skip 'Already absent'
}

Write-Step "5. Re-asserting firewall rule '$AllowAzureRuleName' (0.0.0.0)"
$rule = Invoke-Az @(
    'sql', 'server', 'firewall-rule', 'show',
    '-g', $ResourceGroup, '-s', $ServerName, '-n', $AllowAzureRuleName
) -AllowFailure
if ($rule) {
    Write-Skip 'Already present'
}
else {
    Invoke-Az @(
        'sql', 'server', 'firewall-rule', 'create',
        '-g', $ResourceGroup, '-s', $ServerName, '-n', $AllowAzureRuleName,
        '--start-ip-address', '0.0.0.0', '--end-ip-address', '0.0.0.0'
    ) | Out-Null
    Write-Ok 'Recreated - Beat 3 needs it present so it can be shown to be worthless'
}

Write-Step '6. Repointing the RDP rule at this machine'
Write-Skip 'Different venue means a different egress IP. This is why it re-runs.'
& (Join-Path $PSScriptRoot 'allow-me.ps1')

Write-Step '7. Flushing the DNS cache on the VM'
Invoke-VmScript 'Clear-DnsClientCache; "flushed"' | Out-Null
Write-Ok 'Flushed'

Write-Host ''
Write-Ok 'Reset complete. Now run .\05-verify.ps1 before you rehearse.'
