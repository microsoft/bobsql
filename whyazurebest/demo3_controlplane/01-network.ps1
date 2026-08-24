<#
.SYNOPSIS
    Step 1 of 6. Creates the VNet, both subnets, and the client NSG.

.DESCRIPTION
    Runs from the presenter's laptop. Control plane only - no SQL connection.

    Deliberately creates NO private endpoint, NO private DNS zone, and NO DNS
    VNet link. Those are Beats 2 and 5 and must not exist before the demo runs.

.NOTES
    snet-data has private-endpoint network policies Disabled. That is a
    prerequisite for attaching a private endpoint later, and it is inert until
    one exists, so it does not spoil Beat 2.
#>

. "$PSScriptRoot\00-config.ps1"

Write-Step "Selecting subscription"
Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null
Write-Ok $SubscriptionId

Write-Step "Resource group '$ResourceGroup'"
$rg = Invoke-Az @('group', 'show', '--name', $ResourceGroup) -AllowFailure
if ($rg) {
    Write-Skip "Already exists in $($rg.location)"
}
else {
    Invoke-Az @('group', 'create', '--name', $ResourceGroup, '--location', $Location) | Out-Null
    Write-Ok "Created in $Location"
}

Write-Step "VNet '$VNetName' ($VNetPrefix) with subnet '$DataSubnet' ($DataPrefix)"
$vnet = Invoke-Az @('network', 'vnet', 'show', '-g', $ResourceGroup, '-n', $VNetName) -AllowFailure
if ($vnet) {
    # Existence alone is not enough. A VNet left over in another region skips
    # this block and then fails much later with InvalidResourceReference.
    if ($vnet.location -ne $Location) {
        Write-Fail "Exists in '$($vnet.location)' but this demo needs '$Location'"
        throw "Delete it first: az network vnet delete -g $ResourceGroup -n $VNetName"
    }
    Write-Skip 'Already exists'
}
else {
    Invoke-Az @(
        'network', 'vnet', 'create',
        '-g', $ResourceGroup,
        '-n', $VNetName,
        # Explicit. Every az *-create defaults to the resource group's location,
        # and this resource group is in eastus.
        '--location', $Location,
        '--address-prefix', $VNetPrefix,
        '--subnet-name', $DataSubnet,
        '--subnet-prefix', $DataPrefix
    ) | Out-Null
    Write-Ok 'Created'
}

Write-Step "Subnet '$ClientSubnet' ($ClientPrefix)"
# Must not be named $clientSubnet - PowerShell variable names are
# case-insensitive and that would clobber $ClientSubnet from 00-config.ps1.
$existingClient = Invoke-Az @(
    'network', 'vnet', 'subnet', 'show',
    '-g', $ResourceGroup, '--vnet-name', $VNetName, '--name', $ClientSubnet
) -AllowFailure
if ($existingClient) {
    Write-Skip 'Already exists'
}
else {
    Invoke-Az @(
        'network', 'vnet', 'subnet', 'create',
        '-g', $ResourceGroup,
        '--vnet-name', $VNetName,
        '--name', $ClientSubnet,
        '--address-prefix', $ClientPrefix
    ) | Out-Null
    Write-Ok 'Created'
}

Write-Step "NSG '$NsgName'"
$nsg = Invoke-Az @('network', 'nsg', 'show', '-g', $ResourceGroup, '-n', $NsgName) -AllowFailure
if ($nsg) {
    if ($nsg.location -ne $Location) {
        Write-Fail "Exists in '$($nsg.location)' but this demo needs '$Location'"
        throw "Delete it first: az network nsg delete -g $ResourceGroup -n $NsgName"
    }
    Write-Skip 'Already exists'
}
else {
    Invoke-Az @('network', 'nsg', 'create', '-g', $ResourceGroup, '-n', $NsgName, '--location', $Location) | Out-Null
    Write-Ok 'Created'
}

Write-Step "Deny rule '$DenyRuleName' (priority 4000)"
$denyRule = Invoke-Az @(
    'network', 'nsg', 'rule', 'show',
    '-g', $ResourceGroup, '--nsg-name', $NsgName, '--name', $DenyRuleName
) -AllowFailure
if ($denyRule) {
    Write-Skip 'Already exists'
}
else {
    Invoke-Az @(
        'network', 'nsg', 'rule', 'create',
        '-g', $ResourceGroup,
        '--nsg-name', $NsgName,
        '--name', $DenyRuleName,
        '--priority', '4000',
        '--direction', 'Inbound',
        '--access', 'Deny',
        '--protocol', '*',
        '--source-address-prefixes', 'Internet',
        '--destination-port-ranges', '*'
    ) | Out-Null
    Write-Ok 'Created - nothing on the internet reaches this subnet by default'
}

Write-Step "Attaching NSG to '$ClientSubnet'"
Invoke-Az @(
    'network', 'vnet', 'subnet', 'update',
    '-g', $ResourceGroup,
    '--vnet-name', $VNetName,
    '--name', $ClientSubnet,
    '--network-security-group', $NsgName
) | Out-Null
Write-Ok 'Attached'

Write-Step "Disabling private-endpoint network policies on '$DataSubnet'"
Invoke-Az @(
    'network', 'vnet', 'subnet', 'update',
    '-g', $ResourceGroup,
    '--vnet-name', $VNetName,
    '--name', $DataSubnet,
    '--private-endpoint-network-policies', 'Disabled'
) | Out-Null
Write-Ok 'Disabled - required before a private endpoint can attach in Beat 2'

Write-Host ''
Write-Ok 'Step 1 complete. Next: .\02-vm.ps1'
