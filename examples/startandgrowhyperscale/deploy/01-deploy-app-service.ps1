[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId, '--output', 'none') | Out-Null

Write-Step "Resource group $ResourceGroup"
$exists = Invoke-Az @('group', 'exists', '--name', $ResourceGroup, '--output', 'tsv') -Raw
if ($exists -ne 'true') {
    Invoke-Az (@('group', 'create', '--name', $ResourceGroup, '--location', $AppLocation, '--tags') + $Tags + @('--output', 'json')) | Out-Null
    Write-Ok 'Created'
}
else { Write-Skip 'Already exists' }

Write-Step "Windows App Service plan $AppServicePlanName"
$plan = Invoke-Az @('appservice', 'plan', 'show', '--resource-group', $ResourceGroup,
    '--name', $AppServicePlanName, '--output', 'json') -AllowFailure
if (-not $plan) {
    $plan = Invoke-Az (@('appservice', 'plan', 'create', '--resource-group', $ResourceGroup,
        '--name', $AppServicePlanName, '--location', $AppLocation, '--sku', $AppSku,
        '--tags') + $Tags + @('--output', 'json'))
    Write-Ok 'Created'
}
else { Write-Skip 'Already exists' }
if ($plan.reserved) { throw "$AppServicePlanName is a Linux plan; Windows is required." }

Write-Step "Windows web app $AppName"
$webApp = Invoke-Az @('webapp', 'show', '--resource-group', $ResourceGroup, '--name', $AppName, '--output', 'json') -AllowFailure
if (-not $webApp) {
    Invoke-Az (@('webapp', 'create', '--resource-group', $ResourceGroup,
        '--plan', $AppServicePlanName, '--name', $AppName, '--tags') + $Tags + @('--output', 'json')) | Out-Null
    Write-Ok 'Created'
}
else { Write-Skip 'Already exists' }

Write-Step 'Configuring the web app for Blazor Server on .NET 10'
Invoke-Az @('webapp', 'identity', 'assign', '--resource-group', $ResourceGroup, '--name', $AppName, '--output', 'json') | Out-Null
Invoke-Az @('webapp', 'config', 'set', '--resource-group', $ResourceGroup, '--name', $AppName,
    '--always-on', 'true', '--ftps-state', 'Disabled', '--min-tls-version', '1.2',
    '--http20-enabled', 'true', '--web-sockets-enabled', 'true',
    '--net-framework-version', 'v10.0', '--output', 'json') | Out-Null
Invoke-Az @('webapp', 'config', 'set', '--resource-group', $ResourceGroup, '--name', $AppName,
    '--generic-configurations', 'healthCheckPath=/healthz', '--output', 'json') | Out-Null
Invoke-Az @('webapp', 'update', '--resource-group', $ResourceGroup, '--name', $AppName,
    '--https-only', 'true', '--client-affinity-enabled', 'true', '--output', 'json') | Out-Null
Invoke-Az @('webapp', 'config', 'appsettings', 'set', '--resource-group', $ResourceGroup, '--name', $AppName,
    '--settings', "Demo__Mode=$DemoMode", 'WEBSITE_RUN_FROM_PACKAGE=1',
    "ServerlessMonitor__ResourceId=/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Sql/servers/$SqlServerName/databases/$CaldovaDatabase",
    "ConnectionStrings__Scheduling=Server=tcp:$SqlServerFqdn,1433;Initial Catalog=$CaldovaDatabase;Authentication=Active Directory Managed Identity;Encrypt=True;TrustServerCertificate=False;Connect Timeout=30",
    '--output', 'json') | Out-Null
Write-Ok 'WebSockets, ARR affinity, HTTPS-only, Always On, health check /healthz'

Write-Host "`nApp Service ready: $AppUrl" -ForegroundColor Green
Write-Host 'Next: run 02-publish-app.ps1.'
