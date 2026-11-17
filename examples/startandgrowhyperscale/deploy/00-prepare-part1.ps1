[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param()

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"

if ($Part1SqlServerName -eq $SqlServerName) {
    throw 'The Start server must be separate from the Grow server.'
}

$serverId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Sql/servers/$Part1SqlServerName"

function Assert-Part1Server {
    param($Server)
    if ($Server.id -ne $serverId -or ($Server.location -replace '\s', '') -ne $SqlLocation) {
        throw 'Start server identity or region does not match the plan.'
    }
    if ($Server.minimalTlsVersion -ne '1.2' -or $Server.publicNetworkAccess -ne 'Enabled') {
        throw 'Start server must use TLS 1.2 and have its public endpoint enabled. No settings were changed.'
    }
    $auth = Invoke-Az @('sql', 'server', 'ad-only-auth', 'get', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroup, '--name', $Part1SqlServerName, '--output', 'json')
    if ($auth.azureADOnlyAuthentication -ne $true) {
        throw 'Start server must use Microsoft Entra-only authentication. No settings were changed.'
    }
}

$groupExists = Invoke-Az @('group', 'exists', '--subscription', $SubscriptionId,
    '--name', $ResourceGroup, '--output', 'tsv') -Raw
if ($groupExists -notin @('true', 'false')) { throw 'Unexpected resource-group existence response.' }
$server = if ($groupExists -eq 'true') {
    $servers = @(Invoke-Az @('sql', 'server', 'list', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroup, '--output', 'json'))
    $servers | Where-Object { $_.name -eq $Part1SqlServerName }
}
if ($server) { Assert-Part1Server $server }

Write-Step 'Off-camera preparation plan'
[pscustomobject]@{
    Subscription = $SubscriptionId
    ResourceGroup = "$ResourceGroup ($(if ($groupExists -eq 'true') { 'reuse' } else { 'create' }))"
    Server = "$Part1SqlServerFqdn ($(if ($server) { 'reuse' } else { 'create' }))"
    Region = $SqlLocation
    Security = 'Microsoft Entra-only; TLS 1.2; public endpoint; no firewall rules added'
    Kept = 'All existing databases, Grow resources, and resource-group settings'
    Excluded = 'No database creation, schema, data, app publishing, or pool changes'
} | Format-List | Out-String | Write-Host

if ($groupExists -eq 'false' -and $PSCmdlet.ShouldProcess($ResourceGroup, 'Create resource group')) {
    Invoke-Az (@('group', 'create', '--subscription', $SubscriptionId, '--name', $ResourceGroup,
        '--location', $SqlLocation, '--tags') + $Tags + @('--output', 'json')) | Out-Null
    $verifiedGroup = Invoke-Az @('group', 'exists', '--subscription', $SubscriptionId,
        '--name', $ResourceGroup, '--output', 'tsv') -Raw
    if ($verifiedGroup -ne 'true') { throw 'Resource group creation could not be verified.' }
}

if (-not $server -and $PSCmdlet.ShouldProcess($serverId, 'Create Start logical server (Microsoft Entra-only)')) {
    if ((Invoke-Az @('group', 'exists', '--subscription', $SubscriptionId,
        '--name', $ResourceGroup, '--output', 'tsv') -Raw) -ne 'true') {
        throw 'Resource group must exist before creating the Start logical server.'
    }
    $user = Invoke-Az @('ad', 'signed-in-user', 'show', '--output', 'json')
    if (-not $user.id -or -not $user.userPrincipalName) {
        throw 'A signed-in Entra user is required as the Start server administrator.'
    }
    Invoke-Az (@('sql', 'server', 'create', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroup, '--name', $Part1SqlServerName, '--location', $SqlLocation,
        '--enable-ad-only-auth', '--external-admin-principal-type', 'User',
        '--external-admin-name', $user.userPrincipalName, '--external-admin-sid', $user.id,
        '--assign-identity', '--minimal-tls-version', '1.2', '--enable-public-network', 'true',
        '--tags') + $Tags + @('part=start', '--output', 'json')) | Out-Null
    $server = Invoke-Az @('sql', 'server', 'show', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroup, '--name', $Part1SqlServerName, '--output', 'json')
    Assert-Part1Server $server
}

if ($WhatIfPreference) {
    Write-Host 'Plan only: no Azure resources changed.' -ForegroundColor Yellow
}
elseif ($server) {
    Write-Ok "Resource group and Start logical server verified. No database was created. Server: $serverId"
}
else {
    throw 'Preparation did not complete; the Start logical server is absent.'
}
