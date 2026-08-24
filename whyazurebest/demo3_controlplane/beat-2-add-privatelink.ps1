<#
.SYNOPSIS
    BEAT 2. Adds the private endpoint and the private DNS zone - and breaks nothing.

.DESCRIPTION
    Runs from the presenter's LAPTOP. Control plane only.

    Creates three things:
      1. A private endpoint for the logical server in snet-data
      2. The privatelink.database.windows.net private DNS zone
      3. A DNS zone group, so the A record is written and maintained for us

    It deliberately does NOT create the VNet link. That is Beat 5, and holding
    it back is what makes Beat 4 land.

.NOTES
    Learn: "When adding a Private endpoint connection, public routing to your
    Azure SQL server isn't blocked by default." That is the whole point of this
    beat - after it runs, go back to the VM and the query still works.
#>

. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

Write-Beat 'BEAT 2  Add Private Link. Change nothing else.'

$serverId = & az sql server show -g $ResourceGroup -n $ServerName --query id -o tsv 2>&1
if ($LASTEXITCODE -ne 0) { throw "Could not find server '$ServerName'.`n$serverId" }
$serverId = ($serverId | Out-String).Trim()

Write-Step "Private endpoint '$PeName' in '$DataSubnet'"
$pe = Invoke-Az @('network', 'private-endpoint', 'show', '-g', $ResourceGroup, '-n', $PeName) -AllowFailure
if ($pe) {
    Write-Skip 'Already exists'
}
else {
    Show-Command "az network private-endpoint create -n $PeName --vnet-name $VNetName --subnet $DataSubnet --group-id sqlServer"
    Invoke-Az @(
        'network', 'private-endpoint', 'create',
        '-g', $ResourceGroup,
        '-n', $PeName,
        # Explicit for the same reason as the VM: this defaults to the resource
        # group's location, while snet-data may live in a different region.
        '--location', $Location,
        '--vnet-name', $VNetName,
        '--subnet', $DataSubnet,
        '--private-connection-resource-id', $serverId,
        '--group-id', 'sqlServer',
        '--connection-name', $PeConnection
    ) | Out-Null
    Write-Ok 'Created'
}

Write-Step 'Private IP assigned to the endpoint'
$peIp = & az network private-endpoint show -g $ResourceGroup -n $PeName `
    --query 'customDnsConfigs[0].ipAddresses[0]' -o tsv 2>&1
$peIp = ($peIp | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($peIp)) {
    $nicId = (& az network private-endpoint show -g $ResourceGroup -n $PeName `
        --query 'networkInterfaces[0].id' -o tsv 2>&1 | Out-String).Trim()
    $peIp = (& az network nic show --ids $nicId `
        --query 'ipConfigurations[0].privateIPAddress' -o tsv 2>&1 | Out-String).Trim()
}
Write-Ok "$peIp"

Write-Step "Private DNS zone '$PrivateDnsZone'"
$zone = Invoke-Az @('network', 'private-dns', 'zone', 'show', '-g', $ResourceGroup, '-n', $PrivateDnsZone) -AllowFailure
if ($zone) {
    Write-Skip 'Already exists'
}
else {
    Invoke-Az @('network', 'private-dns', 'zone', 'create', '-g', $ResourceGroup, '-n', $PrivateDnsZone) | Out-Null
    Write-Ok 'Created'
}

Write-Step "DNS zone group '$DnsZoneGroup'"
$zg = Invoke-Az @(
    'network', 'private-endpoint', 'dns-zone-group', 'show',
    '-g', $ResourceGroup, '--endpoint-name', $PeName, '-n', $DnsZoneGroup
) -AllowFailure
if ($zg) {
    Write-Skip 'Already exists'
}
else {
    Invoke-Az @(
        'network', 'private-endpoint', 'dns-zone-group', 'create',
        '-g', $ResourceGroup,
        '--endpoint-name', $PeName,
        '-n', $DnsZoneGroup,
        '--private-dns-zone', $PrivateDnsZone,
        '--zone-name', 'sql'
    ) | Out-Null
    Write-Ok 'Created - the A record is now written and maintained for us'
}

Write-Step 'A records in the private zone'
$records = Invoke-Az @('network', 'private-dns', 'record-set', 'a', 'list', '-g', $ResourceGroup, '-z', $PrivateDnsZone)
foreach ($r in $records) {
    Write-Ok "$($r.name).$PrivateDnsZone -> $($r.aRecords.ipv4Address -join ', ')"
}

Write-Step 'VNet links on the private zone'
$links = Invoke-Az @('network', 'private-dns', 'link', 'vnet', 'list', '-g', $ResourceGroup, '-z', $PrivateDnsZone)
if ($links) {
    Write-Warn "$($links.Count) link(s) exist. Beat 4 will not land. Run .\reset-demo.ps1."
}
else {
    Write-Ok 'None. Correct - the link is Beat 5.'
}

Write-Host ''
Write-Host '  Now go to the RDP window and run:  .\query.ps1' -ForegroundColor Cyan
Write-Host ''
Write-Host '  Adding Private Link broke nothing.' -ForegroundColor White
Write-Host ''
