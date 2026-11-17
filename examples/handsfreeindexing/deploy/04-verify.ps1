[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId, '--output', 'none') | Out-Null

Write-Step 'Azure SQL Database'
$database = Invoke-Az @('sql', 'db', 'show', '--resource-group', $ResourceGroup, '--server', $SqlServerName,
    '--name', $DatabaseName, '--output', 'json')
if ($database.status -ne 'Online') { throw "Database status is $($database.status)." }
if ($database.sku.tier -ne 'Hyperscale' -or $database.sku.capacity -ne $DatabaseVCoreCapacity) {
    throw "Expected $DatabaseVCoreCapacity-vCore Hyperscale; found $($database.currentServiceObjectiveName)."
}
Write-Ok "$($database.currentServiceObjectiveName), Online"

$adOnly = Invoke-Az @('sql', 'server', 'ad-only-auth', 'get', '--resource-group', $ResourceGroup,
    '--name', $SqlServerName, '--query', 'azureAdOnlyAuthentication', '--output', 'tsv') -Raw
if ($adOnly -ne 'True') { throw "Entra-only authentication is not enabled." }
Write-Ok 'Entra-only authentication enabled'

Write-Step 'Private SQL connectivity'
$connectionState = Invoke-Az @('network', 'private-endpoint-connection', 'list', '--resource-group', $ResourceGroup,
    '--name', $SqlServerName, '--type', 'Microsoft.Sql/servers',
    '--query', '[0].properties.privateLinkServiceConnectionState.status', '--output', 'tsv') -Raw
if ($connectionState -ne 'Approved') { throw "Private endpoint state is '$connectionState'." }
Write-Ok 'Private endpoint approved'

Write-Step 'Windows App Service'
$app = Invoke-Az @('webapp', 'show', '--resource-group', $ResourceGroup, '--name', $AppName, '--output', 'json')
if ($app.state -ne 'Running') { throw "App Service state is $($app.state)." }
$plan = Invoke-Az @('appservice', 'plan', 'show', '--resource-group', $ResourceGroup,
    '--name', $AppServicePlanName, '--output', 'json')
if ($plan.reserved) { throw 'App Service plan is Linux; Windows is required.' }
Write-Ok "Running on Windows $($plan.sku.name)"

Write-Step 'Application health'
$health = Invoke-RestMethod -Uri "$AppUrl/healthz" -TimeoutSec 60
if ($health.status -ne 'ok') { throw '/healthz did not report ok.' }
Write-Ok '/healthz = ok'

$readiness = Invoke-RestMethod -Uri "$AppUrl/readyz" -TimeoutSec 60
if ($readiness.status -ne 'ready') { throw '/readyz did not report ready.' }
Write-Ok '/readyz = ready; Azure SQL reachable through managed identity'

Write-Host "`nVerification passed: $AppUrl" -ForegroundColor Green
