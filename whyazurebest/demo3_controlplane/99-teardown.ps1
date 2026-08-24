<#
.SYNOPSIS
    Delete everything this demo created. Requires an explicit -Confirm switch.

.DESCRIPTION
    Deletes, in dependency order:
        vm-demo3-client (+ its NIC, disk, public IP)
        pe-sql-demo3, the private DNS zone and its VNet link
        bwpehyperscale-srv and the bwpehyperscale database
        vnet-demo3, nsg-demo3-client

    Does NOT delete the resource group. bwsqlestaterg holds resources that
    demo1_azureestate counts, and deleting the group would destroy them.

    Deleting the logical server ALSO removes the Hyperscale database and its
    backups. There is no undo.

.NOTES
    After teardown, demo1's estate tile counts drop by 1 logical server and
    1 database. Re-run demo1's verify-estate-counts.ps1 if that recording
    matters.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [switch]$Confirm
)

. "$PSScriptRoot\00-config.ps1"

if (-not $Confirm) { throw 'Re-run with -Confirm to actually delete resources.' }

Invoke-Az @('account','set','--subscription',$SubscriptionId) | Out-Null

Write-Host ''
Write-Warn "About to permanently delete demo3 resources from $ResourceGroup."
Write-Warn "This destroys the $DatabaseName database and all of its backups."
$answer = Read-Host "Type the database name ($DatabaseName) to proceed"
if ($answer -ne $DatabaseName) { Write-Host 'Aborted.' -ForegroundColor Yellow; exit 1 }

Write-Step "Virtual machine $VmName"
Invoke-Az @('vm','delete','--resource-group',$ResourceGroup,'--name',$VmName,'--yes') -AllowFailure | Out-Null
Write-Ok 'Deleted (or was already gone)'

Write-Step 'Orphaned VM disks, NICs, and public IPs'
$disks = Invoke-Az @('disk','list','--resource-group',$ResourceGroup) -AllowFailure
foreach ($d in @($disks | Where-Object { $_.name -like "$VmName*" })) {
    Invoke-Az @('disk','delete','--resource-group',$ResourceGroup,'--name',$d.name,'--yes') -AllowFailure | Out-Null
    Write-Ok "Deleted disk $($d.name)"
}
$nics = Invoke-Az @('network','nic','list','--resource-group',$ResourceGroup) -AllowFailure
foreach ($n in @($nics | Where-Object { $_.name -like "$VmName*" })) {
    Invoke-Az @('network','nic','delete','--resource-group',$ResourceGroup,'--name',$n.name) -AllowFailure | Out-Null
    Write-Ok "Deleted NIC $($n.name)"
}
$ips = Invoke-Az @('network','public-ip','list','--resource-group',$ResourceGroup) -AllowFailure
foreach ($p in @($ips | Where-Object { $_.name -like "$VmName*" })) {
    Invoke-Az @('network','public-ip','delete','--resource-group',$ResourceGroup,'--name',$p.name) -AllowFailure | Out-Null
    Write-Ok "Deleted public IP $($p.name)"
}

Write-Step "Private endpoint $PeName"
Invoke-Az @('network','private-endpoint','delete','--resource-group',$ResourceGroup,'--name',$PeName) -AllowFailure | Out-Null
Write-Ok 'Deleted'

Write-Step "Private DNS zone $PrivateDnsZone"
Invoke-Az @('network','private-dns','link','vnet','delete','--resource-group',$ResourceGroup,'--zone-name',$PrivateDnsZone,'--name',$DnsLinkName,'--yes') -AllowFailure | Out-Null
Invoke-Az @('network','private-dns','zone','delete','--resource-group',$ResourceGroup,'--name',$PrivateDnsZone,'--yes') -AllowFailure | Out-Null
Write-Ok 'Deleted'

Write-Step "Logical server $ServerName (and $DatabaseName)"
Invoke-Az @('sql','server','delete','--resource-group',$ResourceGroup,'--name',$ServerName,'--yes') -AllowFailure | Out-Null
Write-Ok 'Deleted'

Write-Step "Virtual network $VNetName"
Invoke-Az @('network','vnet','delete','--resource-group',$ResourceGroup,'--name',$VNetName) -AllowFailure | Out-Null
Write-Ok 'Deleted'

Write-Step "Network security group $NsgName"
Invoke-Az @('network','nsg','delete','--resource-group',$ResourceGroup,'--name',$NsgName) -AllowFailure | Out-Null
Write-Ok 'Deleted'

Write-Step 'Generated RDP file'
if (Test-Path $RdpFilePath) {
    Remove-Item $RdpFilePath -Force
    Write-Ok 'Removed'
}
else {
    Write-Skip 'None'
}

Write-Host "`nTeardown complete. Resource group $ResourceGroup was left in place." -ForegroundColor Cyan
