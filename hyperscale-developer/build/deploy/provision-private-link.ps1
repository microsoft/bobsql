<#
    Ward General Hospital — Hyperscale developer demo
    provision-private-link.ps1 : put an Azure Private Link (private endpoint) in
                                 front of the Collier Health logical server so the
                                 wardgeneral Hyperscale database is reachable over a
                                 PRIVATE IP inside a VNet — the "Secure it" story.

    WHY (the security story):
      The app connects passwordless (managed identity), but the server still has a
      PUBLIC endpoint guarded by firewall rules. Private Link gives the logical
      server a private IP on your VNet and lets you (optionally) turn the public
      endpoint OFF entirely — "no public network path", exactly as the architecture
      diagram claims. Learn: "Azure Private Link for Azure SQL Database."

    SCOPE — the private endpoint targets the LOGICAL SERVER (group-id sqlServer), so
      it covers EVERY database on collierhealth-17: the wardgeneral primary AND a
      same-server named replica (wardgeneral-research), if/when it is created. One
      endpoint, one DNS record, both databases. (A named replica placed on a
      SEPARATE logical server would need its own private endpoint.)

    DEMO SAFETY — public access is LEFT ON by default. A private endpoint is only
      reachable from inside the VNet / a peered VNet / on-prem over VPN/ExpressRoute
      (Learn). A laptop on a conference network is NOT in the VNet, so flipping
      public access OFF would immediately break the running app, sqlsim, and the
      MSSQL extension. This script provisions the endpoint so you can SHOW it in the
      portal (private IP, approved connection, DNS) while the demo keeps working over
      the public endpoint. Pass -DenyPublic ONLY when the app runs inside the VNet.

    COST: the VNet + Private DNS zone are effectively free; a private endpoint has a
      small hourly + per-GB charge. Remove everything by deleting the VNet, the
      private endpoint, and the private DNS zone (see the teardown block at the end,
      commented).

    Prerequisites: az login + az account set -s <subscription>. All data synthetic.

    Verified CLI — Learn "Tutorial: Connect to an Azure SQL server using an Azure
    Private Endpoint (CLI)" (accessed 2026-07-21):
      az network private-endpoint create ... --group-id sqlServer
      az network private-endpoint dns-zone-group create ... --private-dns-zone privatelink.database.windows.net
#>
[CmdletBinding()]
param(
    [string] $Rg          = 'rg-collierhealth',
    [string] $Server      = 'collierhealth-17',                # logical server (primary + same-server replica)
    [string] $Loc         = 'centralus',                       # MUST match the server's region
    [string] $Vnet        = 'vnet-collierhealth',
    [string] $Subnet      = 'snet-sql',
    [string] $VnetCidr    = '10.42.0.0/16',
    [string] $SubnetCidr  = '10.42.1.0/24',
    [string] $Pe          = 'pe-collierhealth-sql',
    [string] $DnsZone     = 'privatelink.database.windows.net',
    [switch] $DenyPublic                                        # DANGER: breaks laptop connectivity — only when app is in-VNet
)

$ErrorActionPreference = 'Stop'
$connName  = "$Pe-conn"
$zoneGroup = 'default'
$vnetLink  = "$Vnet-link"

Write-Host "=== Private Link for $Server ($Loc) ==="
Write-Host "  vnet/subnet : $Vnet / $Subnet  ($SubnetCidr)"
Write-Host "  endpoint    : $Pe  ->  sqlServer  (covers ALL databases on the server)"
Write-Host "  dns zone    : $DnsZone"
Write-Host "  public path : $(if ($DenyPublic) { 'WILL BE DISABLED (-DenyPublic)' } else { 'left ENABLED (demo-safe)' })"
Write-Host ""

# Resource id of the logical server (the private-endpoint target).
$serverId = az sql server show --resource-group $Rg --name $Server --query id -o tsv
if (-not $serverId) { throw "Could not find logical server $Server in $Rg." }

# 1) VNet + subnet to host the private endpoint.
Write-Host "--- 1/5  VNet + subnet ---"
az network vnet create `
    --resource-group $Rg --name $Vnet --location $Loc `
    --address-prefixes $VnetCidr `
    --subnet-name $Subnet --subnet-prefixes $SubnetCidr -o table

# A subnet that hosts a private endpoint must not enforce PE network policies.
az network vnet subnet update `
    --resource-group $Rg --vnet-name $Vnet --name $Subnet `
    --private-endpoint-network-policies Disabled -o none

# 2) The private endpoint -> the logical server (group-id sqlServer).
Write-Host "--- 2/5  Private endpoint ---"
az network private-endpoint create `
    --resource-group $Rg --name $Pe --location $Loc `
    --vnet-name $Vnet --subnet $Subnet `
    --private-connection-resource-id $serverId `
    --group-id sqlServer `
    --connection-name $connName -o table

# 3) Private DNS zone for SQL private endpoints.
Write-Host "--- 3/5  Private DNS zone ---"
az network private-dns zone create `
    --resource-group $Rg --name $DnsZone -o none

# 4) Link the zone to the VNet so names resolve inside it.
Write-Host "--- 4/5  Link DNS zone to VNet ---"
az network private-dns link vnet create `
    --resource-group $Rg --zone-name $DnsZone `
    --name $vnetLink --virtual-network $Vnet `
    --registration-enabled false -o none

# 5) DNS zone group — auto-creates the A record (server FQDN -> private IP).
Write-Host "--- 5/5  DNS zone group (A record) ---"
az network private-endpoint dns-zone-group create `
    --resource-group $Rg --endpoint-name $Pe `
    --name $zoneGroup --private-dns-zone $DnsZone --zone-name sql -o none

# Optional: cut the public path. Only safe when the CLIENT is inside the VNet.
if ($DenyPublic) {
    Write-Host "--- Disabling PUBLIC network access on $Server (-DenyPublic) ---" -ForegroundColor Yellow
    az sql server update --resource-group $Rg --name $Server --set publicNetworkAccess=Disabled -o none
}

# ---- Summary -------------------------------------------------------------
Write-Host ""
Write-Host "=== Result ==="
$state = az network private-endpoint show --resource-group $Rg --name $Pe `
    --query "{provisioning:provisioningState, connection:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" -o json
Write-Host $state
$ip = az network private-endpoint show --resource-group $Rg --name $Pe `
    --query "customDnsConfigs[0].ipAddresses[0]" -o tsv
Write-Host "  $Server.$($DnsZone -replace '^privatelink\.','') -> private IP $ip"
$pub = az sql server show --resource-group $Rg --name $Server --query publicNetworkAccess -o tsv
Write-Host "  publicNetworkAccess = $pub  (Enabled keeps the laptop demo working)"
Write-Host ""
Write-Host "Portal: $Server > Networking > Private access — the connection shows Approved."
Write-Host "Reaching it privately requires a client inside $Vnet (VM / App Service VNet-integration / VPN)."

# ---- Teardown (uncomment to remove) --------------------------------------
# az network private-endpoint delete -g $Rg -n $Pe
# az network private-dns link vnet delete -g $Rg --zone-name $DnsZone --name $vnetLink --yes
# az network private-dns zone delete -g $Rg -n $DnsZone --yes
# az network vnet delete -g $Rg -n $Vnet
# az sql server update -g $Rg -n $Server --set publicNetworkAccess=Enabled -o none
