[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"

$app = Invoke-Az @('webapp', 'show', '--subscription', $SubscriptionId,
    '--resource-group', $ResourceGroup, '--name', $AppName, '--output', 'json')
if (-not $app.identity.principalId) { throw "$AppName must have its managed identity assigned first." }

$addresses = @($app.outboundIpAddresses -split ',' | Where-Object { $_ } | Sort-Object -Unique)
if ($addresses.Count -eq 0) { throw 'App Service did not return outbound addresses; no firewall changes were made.' }
foreach ($address in $addresses) {
    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($address, [ref]$parsed) -or
        $parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Invalid App Service outbound IPv4 address: $address"
    }
}

foreach ($address in $addresses) {
    Write-Step "Allow app outbound address $address (single-address SQL firewall rule)"
    Invoke-Az @('sql', 'server', 'firewall-rule', 'create', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroup, '--server', $SqlServerName,
        '--name', "CaldovaApp-$($address -replace '\.', '-')",
        '--start-ip-address', $address, '--end-ip-address', $address, '--output', 'json') | Out-Null
}

Write-Step 'Configure passwordless SQL access with the app managed identity'
Invoke-Az @('webapp', 'config', 'appsettings', 'set', '--subscription', $SubscriptionId,
    '--resource-group', $ResourceGroup, '--name', $AppName, '--settings',
    "ConnectionStrings__Scheduling=Server=tcp:$SqlServerFqdn,1433;Initial Catalog=$CaldovaDatabase;Authentication=Active Directory Managed Identity;Encrypt=True;TrustServerCertificate=False;Connect Timeout=30",
    '--output', 'json') | Out-Null
Write-Ok 'App SQL configuration complete. Entra-only authentication remains enabled.'
