[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\00-config.ps1"

$demoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$setupScript = Join-Path $demoRoot '00-setup.sql'
$grantTemplate = Join-Path $demoRoot '07-grant-app-identity.sql'

foreach ($path in $setupScript, $grantTemplate) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file not found: $path" }
}

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId, '--output', 'none') | Out-Null
$database = Invoke-Az @('sql', 'db', 'show', '--resource-group', $ResourceGroup, '--server', $SqlServerName,
    '--name', $DatabaseName, '--output', 'json')
if ($database.status -ne 'Online') { throw "$DatabaseName is not online. Current status: $($database.status)" }

$principalId = Invoke-Az @('webapp', 'identity', 'show', '--resource-group', $ResourceGroup,
    '--name', $AppName, '--query', 'principalId', '--output', 'tsv') -Raw
$appClientId = Invoke-Az @('ad', 'sp', 'show', '--id', $principalId, '--query', 'appId', '--output', 'tsv') -Raw
if (-not $appClientId) { throw "Could not resolve the application ID for App Service principal $principalId." }

Write-Step 'Deploying the real two-million-row patient-access workload'
Invoke-DemoSqlFile -Path $setupScript
Write-Ok 'Schema, workload data, telemetry procedures, and automatic tuning configuration deployed'

Write-Step "Granting least-privilege procedure access to $AppName"
$template = [IO.File]::ReadAllText($grantTemplate)
$grantSql = $template.Replace('$(AppClientId)', $appClientId).Replace('$(AppName)', $AppName)
$tempGrant = Join-Path ([IO.Path]::GetTempPath()) "caldova-grant-$PID.sql"
try {
    [IO.File]::WriteAllText($tempGrant, $grantSql, [Text.UTF8Encoding]::new($false))
    Invoke-DemoSqlFile -Path $tempGrant
}
finally {
    Remove-Item -LiteralPath $tempGrant -Force -ErrorAction SilentlyContinue
}
Write-Ok "Database user created with application ID $appClientId"

Write-Host "`nDatabase initialization complete." -ForegroundColor Green
Write-Host 'The app identity has EXECUTE permission only on the dashboard and telemetry procedures.'
Write-Host "The exact-IP firewall rule '$BootstrapFirewallRuleName' remains for live presenter scripts."
