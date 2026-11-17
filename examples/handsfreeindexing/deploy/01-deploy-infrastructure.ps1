[CmdletBinding()]
param(
    [string]$ClientIp
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"

Write-Host 'Caldova Hands-Free Indexing: Azure infrastructure' -ForegroundColor Cyan
Invoke-Az @('account', 'set', '--subscription', $SubscriptionId, '--output', 'none') | Out-Null

$account = Invoke-Az @('account', 'show', '--query', '{id:id,name:name,user:user.name}', '--output', 'json')
$signedInUser = Invoke-Az @('ad', 'signed-in-user', 'show', '--query', '{displayName:displayName,id:id,userPrincipalName:userPrincipalName}', '--output', 'json')
Write-Ok "Subscription: $($account.name) ($($account.id))"
Write-Ok "SQL admin: $($signedInUser.userPrincipalName)"

Write-Step "Resource group $ResourceGroup"
$groupExists = Invoke-Az @('group', 'exists', '--name', $ResourceGroup, '--output', 'tsv') -Raw
if ($groupExists -eq 'true') {
    Write-Skip 'Already exists'
}
else {
    $arguments = @('group', 'create', '--name', $ResourceGroup, '--location', $Location, '--tags') + $Tags + @('--output', 'json')
    Invoke-Az $arguments | Out-Null
    Write-Ok 'Created'
}

Write-Step "SQL virtual network $VirtualNetworkName"
$vnet = Invoke-Az @('network', 'vnet', 'show', '--resource-group', $ResourceGroup, '--name', $VirtualNetworkName, '--output', 'json') -AllowFailure
if (-not $vnet) {
    Invoke-Az @('network', 'vnet', 'create', '--resource-group', $ResourceGroup, '--name', $VirtualNetworkName,
        '--location', $Location, '--address-prefixes', '10.42.0.0/16', '--subnet-name', $PrivateEndpointSubnetName,
        '--subnet-prefixes', '10.42.2.0/24', '--output', 'json') | Out-Null
    $vnet = Invoke-Az @('network', 'vnet', 'show', '--resource-group', $ResourceGroup,
        '--name', $VirtualNetworkName, '--output', 'json')
    Write-Ok 'Created'
}
else { Write-Skip 'Already exists' }

Write-Step "App Service integration virtual network $AppVirtualNetworkName"
$appVnet = Invoke-Az @('network', 'vnet', 'show', '--resource-group', $ResourceGroup,
    '--name', $AppVirtualNetworkName, '--output', 'json') -AllowFailure
if (-not $appVnet) {
    Invoke-Az @('network', 'vnet', 'create', '--resource-group', $ResourceGroup,
        '--name', $AppVirtualNetworkName, '--location', $AppLocation, '--address-prefixes', '10.43.0.0/16',
        '--subnet-name', $AppSubnetName, '--subnet-prefixes', '10.43.1.0/24', '--output', 'json') | Out-Null
    $appVnet = Invoke-Az @('network', 'vnet', 'show', '--resource-group', $ResourceGroup,
        '--name', $AppVirtualNetworkName, '--output', 'json')
    Write-Ok 'Created'
}
else { Write-Skip 'Already exists' }

$appSubnet = Invoke-Az @('network', 'vnet', 'subnet', 'show', '--resource-group', $ResourceGroup,
    '--vnet-name', $AppVirtualNetworkName, '--name', $AppSubnetName, '--output', 'json') -AllowFailure
if (-not $appSubnet) {
    Invoke-Az @('network', 'vnet', 'subnet', 'create', '--resource-group', $ResourceGroup,
        '--vnet-name', $AppVirtualNetworkName, '--name', $AppSubnetName, '--address-prefixes', '10.43.1.0/24',
        '--delegations', 'Microsoft.Web/serverFarms', '--output', 'json') | Out-Null
}
else {
    Invoke-Az @('network', 'vnet', 'subnet', 'update', '--resource-group', $ResourceGroup,
        '--vnet-name', $AppVirtualNetworkName, '--name', $AppSubnetName,
        '--delegations', 'Microsoft.Web/serverFarms', '--output', 'json') | Out-Null
}
Write-Ok 'App Service integration subnet ready'

$privateSubnet = Invoke-Az @('network', 'vnet', 'subnet', 'show', '--resource-group', $ResourceGroup,
    '--vnet-name', $VirtualNetworkName, '--name', $PrivateEndpointSubnetName, '--output', 'json') -AllowFailure
if (-not $privateSubnet) {
    Invoke-Az @('network', 'vnet', 'subnet', 'create', '--resource-group', $ResourceGroup,
        '--vnet-name', $VirtualNetworkName, '--name', $PrivateEndpointSubnetName,
        '--address-prefixes', '10.42.2.0/24', '--disable-private-endpoint-network-policies', 'true',
        '--output', 'json') | Out-Null
}
else {
    Invoke-Az @('network', 'vnet', 'subnet', 'update', '--resource-group', $ResourceGroup,
        '--vnet-name', $VirtualNetworkName, '--name', $PrivateEndpointSubnetName,
        '--disable-private-endpoint-network-policies', 'true', '--output', 'json') | Out-Null
}
Write-Ok 'Private endpoint subnet ready'

Write-Step 'Global VNet peering'
$sqlToAppPeering = Invoke-Az @('network', 'vnet', 'peering', 'show', '--resource-group', $ResourceGroup,
    '--vnet-name', $VirtualNetworkName, '--name', $SqlToAppPeeringName, '--output', 'json') -AllowFailure
if (-not $sqlToAppPeering) {
    Invoke-Az @('network', 'vnet', 'peering', 'create', '--resource-group', $ResourceGroup,
        '--vnet-name', $VirtualNetworkName, '--name', $SqlToAppPeeringName,
        '--remote-vnet', $appVnet.id, '--allow-vnet-access', '--output', 'json') | Out-Null
    Write-Ok 'SQL-to-app peering created'
}
else { Write-Skip 'SQL-to-app peering already exists' }

$appToSqlPeering = Invoke-Az @('network', 'vnet', 'peering', 'show', '--resource-group', $ResourceGroup,
    '--vnet-name', $AppVirtualNetworkName, '--name', $AppToSqlPeeringName, '--output', 'json') -AllowFailure
if (-not $appToSqlPeering) {
    Invoke-Az @('network', 'vnet', 'peering', 'create', '--resource-group', $ResourceGroup,
        '--vnet-name', $AppVirtualNetworkName, '--name', $AppToSqlPeeringName,
        '--remote-vnet', $vnet.id, '--allow-vnet-access', '--output', 'json') | Out-Null
    Write-Ok 'App-to-SQL peering created'
}
else { Write-Skip 'App-to-SQL peering already exists' }

Write-Step "Entra-only SQL server $SqlServerName"
$server = Invoke-Az @('sql', 'server', 'show', '--resource-group', $ResourceGroup, '--name', $SqlServerName, '--output', 'json') -AllowFailure
if (-not $server) {
    $arguments = @('sql', 'server', 'create', '--resource-group', $ResourceGroup, '--name', $SqlServerName,
        '--location', $Location, '--enable-ad-only-auth', '--external-admin-principal-type', 'User',
        '--external-admin-name', $signedInUser.displayName, '--external-admin-sid', $signedInUser.id,
        '--assign-identity', '--minimal-tls-version', '1.2', '--enable-public-network', 'true',
        '--tags') + $Tags + @('--output', 'json')
    $server = Invoke-Az $arguments
    Write-Ok 'Created'
}
else { Write-Skip 'Already exists' }

$adOnly = Invoke-Az @('sql', 'server', 'ad-only-auth', 'get', '--resource-group', $ResourceGroup,
    '--name', $SqlServerName, '--query', 'azureAdOnlyAuthentication', '--output', 'tsv') -Raw
if ($adOnly -ne 'True') { throw "Expected Entra-only authentication, found '$adOnly'." }
Write-Ok 'Entra-only authentication verified'

$firewallRule = Invoke-Az @('sql', 'server', 'firewall-rule', 'show', '--resource-group', $ResourceGroup,
    '--server', $SqlServerName, '--name', $BootstrapFirewallRuleName, '--output', 'json') -AllowFailure
if (-not $ClientIp -and $firewallRule) {
    $ClientIp = $firewallRule.startIpAddress
    Write-Step "Temporary bootstrap firewall rule for $ClientIp"
    Write-Skip 'Existing exact-IP rule preserved; use -ClientIp to replace it'
}
else {
    if (-not $ClientIp) { $ClientIp = Get-CurrentClientIp }
    Write-Step "Temporary bootstrap firewall rule for $ClientIp"
    Invoke-Az @('sql', 'server', 'firewall-rule', 'create', '--resource-group', $ResourceGroup,
        '--server', $SqlServerName, '--name', $BootstrapFirewallRuleName,
        '--start-ip-address', $ClientIp, '--end-ip-address', $ClientIp, '--output', 'json') | Out-Null
    Write-Ok 'Created or updated exact-IP rule'
}

Write-Step "Hyperscale database $DatabaseName"
$database = Invoke-Az @('sql', 'db', 'show', '--resource-group', $ResourceGroup, '--server', $SqlServerName,
    '--name', $DatabaseName, '--output', 'json') -AllowFailure
if (-not $database) {
    $arguments = @('sql', 'db', 'create', '--resource-group', $ResourceGroup, '--server', $SqlServerName,
        '--name', $DatabaseName, '--edition', 'Hyperscale', '--compute-model', 'Provisioned', '--family', 'Gen5',
        '--capacity', $DatabaseVCoreCapacity, '--backup-storage-redundancy', 'Local', '--zone-redundant', 'false',
        '--tags') + $Tags + @('--output', 'json')
    $database = Invoke-Az $arguments
    Write-Ok 'Created'
}
else { Write-Skip 'Already exists' }
if ($database.sku.tier -ne 'Hyperscale' -or $database.sku.capacity -ne $DatabaseVCoreCapacity) {
    throw "$DatabaseName exists but is not a $DatabaseVCoreCapacity-vCore Hyperscale database."
}
Write-Ok "$($database.currentServiceObjectiveName), $($database.status)"

Write-Step "Private DNS zone $PrivateDnsZoneName"
$dnsZone = Invoke-Az @('network', 'private-dns', 'zone', 'show', '--resource-group', $ResourceGroup,
    '--name', $PrivateDnsZoneName, '--output', 'json') -AllowFailure
if (-not $dnsZone) {
    $dnsZone = Invoke-Az @('network', 'private-dns', 'zone', 'create', '--resource-group', $ResourceGroup,
        '--name', $PrivateDnsZoneName, '--output', 'json')
    Write-Ok 'Created'
}
else { Write-Skip 'Already exists' }

$link = Invoke-Az @('network', 'private-dns', 'link', 'vnet', 'show', '--resource-group', $ResourceGroup,
    '--zone-name', $PrivateDnsZoneName, '--name', $PrivateDnsLinkName, '--output', 'json') -AllowFailure
if (-not $link) {
    Invoke-Az @('network', 'private-dns', 'link', 'vnet', 'create', '--resource-group', $ResourceGroup,
        '--zone-name', $PrivateDnsZoneName, '--name', $PrivateDnsLinkName,
        '--virtual-network', $VirtualNetworkName, '--registration-enabled', 'false', '--output', 'json') | Out-Null
    Write-Ok 'VNet link created'
}
else { Write-Skip 'VNet link already exists' }

$appLink = Invoke-Az @('network', 'private-dns', 'link', 'vnet', 'show', '--resource-group', $ResourceGroup,
    '--zone-name', $PrivateDnsZoneName, '--name', $AppPrivateDnsLinkName, '--output', 'json') -AllowFailure
if (-not $appLink) {
    Invoke-Az @('network', 'private-dns', 'link', 'vnet', 'create', '--resource-group', $ResourceGroup,
        '--zone-name', $PrivateDnsZoneName, '--name', $AppPrivateDnsLinkName,
        '--virtual-network', $AppVirtualNetworkName, '--registration-enabled', 'false', '--output', 'json') | Out-Null
    Write-Ok 'App VNet link created'
}
else { Write-Skip 'App VNet link already exists' }

Write-Step "SQL private endpoint $PrivateEndpointName"
$serverId = $server.id
$privateEndpoint = Invoke-Az @('network', 'private-endpoint', 'show', '--resource-group', $ResourceGroup,
    '--name', $PrivateEndpointName, '--output', 'json') -AllowFailure
if (-not $privateEndpoint) {
    $privateEndpoint = Invoke-Az @('network', 'private-endpoint', 'create', '--resource-group', $ResourceGroup,
        '--name', $PrivateEndpointName, '--location', $Location, '--vnet-name', $VirtualNetworkName,
        '--subnet', $PrivateEndpointSubnetName, '--private-connection-resource-id', $serverId,
        '--group-id', 'sqlServer', '--connection-name', 'sql-server', '--output', 'json')
    Write-Ok 'Created'
}
else { Write-Skip 'Already exists' }

$zoneGroup = Invoke-Az @('network', 'private-endpoint', 'dns-zone-group', 'show', '--resource-group', $ResourceGroup,
    '--endpoint-name', $PrivateEndpointName, '--name', $PrivateDnsZoneGroupName, '--output', 'json') -AllowFailure
if (-not $zoneGroup) {
    Invoke-Az @('network', 'private-endpoint', 'dns-zone-group', 'create', '--resource-group', $ResourceGroup,
        '--endpoint-name', $PrivateEndpointName, '--name', $PrivateDnsZoneGroupName,
        '--private-dns-zone', $dnsZone.id, '--zone-name', 'sql', '--output', 'json') | Out-Null
    Write-Ok 'DNS zone group created'
}
else { Write-Skip 'DNS zone group already exists' }

Write-Step "Windows App Service plan $AppServicePlanName"
$plan = Invoke-Az @('appservice', 'plan', 'show', '--resource-group', $ResourceGroup,
    '--name', $AppServicePlanName, '--output', 'json') -AllowFailure
if (-not $plan) {
    $plan = Invoke-Az @('appservice', 'plan', 'create', '--resource-group', $ResourceGroup,
        '--name', $AppServicePlanName, '--location', $AppLocation, '--sku', 'S1', '--output', 'json')
    Write-Ok 'Created'
}
else { Write-Skip 'Already exists' }
if ($plan.reserved) { throw "$AppServicePlanName is a Linux plan; Windows is required." }
if (($plan.location -replace '\s', '') -ne $AppLocation -or $plan.sku.name -ne 'S1') {
    throw "$AppServicePlanName must be a Windows S1 plan in $AppLocation."
}

Write-Step "Windows web app $AppName"
$webApp = Invoke-Az @('webapp', 'show', '--resource-group', $ResourceGroup, '--name', $AppName, '--output', 'json') -AllowFailure
if (-not $webApp) {
    $webApp = Invoke-Az @('webapp', 'create', '--resource-group', $ResourceGroup,
        '--plan', $AppServicePlanName, '--name', $AppName, '--output', 'json')
    Write-Ok 'Created'
}
else { Write-Skip 'Already exists' }

Invoke-Az @('webapp', 'identity', 'assign', '--resource-group', $ResourceGroup, '--name', $AppName, '--output', 'json') | Out-Null
Invoke-Az @('webapp', 'config', 'set', '--resource-group', $ResourceGroup, '--name', $AppName,
    '--always-on', 'true', '--ftps-state', 'Disabled', '--min-tls-version', '1.2',
    '--http20-enabled', 'true', '--web-sockets-enabled', 'true',
    '--net-framework-version', 'v10.0', '--output', 'json') | Out-Null
Invoke-Az @('webapp', 'update', '--resource-group', $ResourceGroup, '--name', $AppName,
    '--https-only', 'true', '--client-affinity-enabled', 'true', '--output', 'json') | Out-Null

$integration = Invoke-Az @('webapp', 'vnet-integration', 'list', '--resource-group', $ResourceGroup,
    '--name', $AppName, '--output', 'json')
if (-not ($integration | Where-Object subnetResourceId -match "/subnets/$AppSubnetName$")) {
    Invoke-Az @('webapp', 'vnet-integration', 'add', '--resource-group', $ResourceGroup,
    '--name', $AppName, '--vnet', $AppVirtualNetworkName, '--subnet', $AppSubnetName, '--output', 'json') | Out-Null
}

Invoke-Az @('webapp', 'config', 'set', '--resource-group', $ResourceGroup, '--name', $AppName,
    '--generic-configurations', 'healthCheckPath=/healthz', 'vnetRouteAllEnabled=true', '--output', 'json') | Out-Null

$connectionString = "Server=tcp:$SqlServerFqdn,1433;Initial Catalog=$DatabaseName;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;Authentication=Active Directory Default;"
Invoke-Az @('webapp', 'config', 'appsettings', 'set', '--resource-group', $ResourceGroup, '--name', $AppName,
    '--settings', "ConnectionStrings__Caldova=$connectionString", 'IndexHealthCapture__IntervalSeconds=10',
    'WEBSITE_RUN_FROM_PACKAGE=1', '--output', 'json') | Out-Null

$principalId = Invoke-Az @('webapp', 'identity', 'show', '--resource-group', $ResourceGroup,
    '--name', $AppName, '--query', 'principalId', '--output', 'tsv') -Raw
$appClientId = $null
for ($attempt = 1; $attempt -le 12 -and -not $appClientId; $attempt++) {
    $appClientId = Invoke-Az @('ad', 'sp', 'show', '--id', $principalId, '--query', 'appId', '--output', 'tsv') -Raw -AllowFailure
    if (-not $appClientId) { Start-Sleep -Seconds 5 }
}
if (-not $appClientId) { throw "Could not resolve appId for App Service principal $principalId." }

Write-Host "`nInfrastructure ready" -ForegroundColor Green
Write-Host "Resource group: $ResourceGroup"
Write-Host "SQL server:     $SqlServerFqdn"
Write-Host "Database:       $DatabaseName ($($database.currentServiceObjectiveName))"
Write-Host "App URL:        $AppUrl"
Write-Host "App principal:  $principalId"
Write-Host "App client ID:  $appClientId"
Write-Host "Bootstrap IP:   $ClientIp"
Write-Host "`nNext: run 02-initialize-database.ps1, then 03-publish-app.ps1."
