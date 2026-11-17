[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\00-config.ps1"

$app = Invoke-AzJson @('containerapp', 'show', '--subscription', $ExpectedSubscriptionId,
    '--resource-group', $ResourceGroup, '--name', $DabContainerAppName, '--output', 'json')
$fqdn = $app.properties.configuration.ingress.fqdn
$endpoint = "https://$fqdn/mcp"

Write-Step 'Remote MCP contract for the short-lived demo endpoint'
& (Join-Path $PSScriptRoot '..\dab\invoke-mcp.ps1') -Endpoint $endpoint
if ($LASTEXITCODE -ne 0) { throw 'Remote MCP contract verification failed.' }

Write-Host "`nRemote DAB MCP contract verified at $endpoint." -ForegroundColor Green
Write-Warn 'The endpoint is intentionally anonymous for this short-lived demo. See README.md before sharing or retaining it.'