<#
.SYNOPSIS
    Step 3 of 6. Opens RDP to the demo VM from wherever you are right now,
    and writes demo3.rdp.

.DESCRIPTION
    Detects this machine's public egress IP and points the NSG rule
    'allow-rdp-presenter' at that single /32. Re-run it any time your IP
    changes - a different venue, a different network, a hotel vs a conference
    hall. It is idempotent.

    This is the ONLY inbound path into the demo VM. Everything else on the
    subnet is denied from the internet by 'deny-all-inbound-internet'.

.NOTES
    Run this before you try to RDP in, and again on the morning of the talk.
#>

. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

Write-Step 'Detecting this machine public IP'
$myIp = Get-MyPublicIp
Write-Ok "$myIp"

Write-Step "NSG rule '$RdpRuleName' -> allow TCP 3389 from $myIp/32"
$rule = Invoke-Az @(
    'network', 'nsg', 'rule', 'show',
    '-g', $ResourceGroup, '--nsg-name', $NsgName, '--name', $RdpRuleName
) -AllowFailure

if ($rule) {
    Invoke-Az @(
        'network', 'nsg', 'rule', 'update',
        '-g', $ResourceGroup,
        '--nsg-name', $NsgName,
        '--name', $RdpRuleName,
        '--source-address-prefixes', "$myIp/32"
    ) | Out-Null
    Write-Ok "Updated (was $($rule.sourceAddressPrefix))"
}
else {
    Invoke-Az @(
        'network', 'nsg', 'rule', 'create',
        '-g', $ResourceGroup,
        '--nsg-name', $NsgName,
        '--name', $RdpRuleName,
        '--priority', '100',
        '--direction', 'Inbound',
        '--access', 'Allow',
        '--protocol', 'Tcp',
        '--source-address-prefixes', "$myIp/32",
        '--destination-port-ranges', '3389'
    ) | Out-Null
    Write-Ok 'Created'
}

Write-Step 'Locating the VM public IP'
$vmIp = & az vm list-ip-addresses -g $ResourceGroup -n $VmName `
    --query '[0].virtualMachine.network.publicIpAddresses[0].ipAddress' -o tsv 2>&1
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($vmIp | Out-String).Trim())) {
    Write-Warn "VM '$VmName' does not exist yet. The NSG rule is in place; re-run this after 02-vm.ps1 to get demo3.rdp."
    return
}
$vmIp = ($vmIp | Out-String).Trim()
Write-Ok $vmIp

Write-Step "Writing $RdpFilePath"
@"
full address:s:$vmIp
username:s:$VmAdminUser
prompt for credentials:i:1
administrative session:i:0
screen mode id:i:2
redirectclipboard:i:1
drivestoredirect:s:*
authentication level:i:2
"@ | Set-Content -Path $RdpFilePath -Encoding ASCII
Write-Ok 'Written'

Write-Host ''
Write-Host "  Double-click demo3.rdp, or run:" -ForegroundColor Cyan
Write-Host "      mstsc `"$RdpFilePath`"" -ForegroundColor White
Write-Host ''
Write-Host "  Sign in as '$VmAdminUser' with the password you set in 02-vm.ps1." -ForegroundColor Cyan
Write-Host '  Local drive redirection is on, so you can copy the kit straight across.' -ForegroundColor Cyan
Write-Host ''
