#requires -Version 7.0
<#
    Ward General — run Data API Builder (DAB) LOCALLY for the talk.

    DAB fronts the SAME clinical.* stored procedures the Blazor app calls,
    exposing them as REST (/api), GraphQL (/graphql), and MCP tools (/mcp) with
    NO middle-tier code. For the talk it runs locally (like the app); in Azure it
    belongs in Azure Container Apps / App Service with a managed identity and
    VNet integration (see the architecture slide).

    Passwordless: uses your Entra login (Active Directory Default) — no secret.
    Ctrl+C stops it.

    Usage:
      ./run-dab.ps1
      ./run-dab.ps1 -Server myserver.database.windows.net -Database wardgeneral
#>
[CmdletBinding()]
param(
    [string]$Server   = 'collierhealth-17.database.windows.net',
    [string]$Database = 'wardgeneral',
    [string]$Config   = (Join-Path $PSScriptRoot 'dab-config.json')
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command dab -ErrorAction SilentlyContinue)) {
    throw "DAB CLI not found. Install it with:  dotnet tool install --global Microsoft.DataApiBuilder"
}
if (-not (Test-Path $Config)) { throw "DAB config not found: $Config" }

# Passwordless connection — 'Active Directory Default' picks up your az login /
# VS Code / Azure identity locally. In Azure use 'Active Directory Managed Identity'.
$env:DAB_CONNECTION_STRING =
    "Server=tcp:$Server,1433;Database=$Database;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;"

Write-Host "Starting Data API Builder for $Database on $Server ..." -ForegroundColor Cyan
Write-Host "  REST     http://localhost:5000/api" -ForegroundColor DarkGray
Write-Host "  GraphQL  http://localhost:5000/graphql" -ForegroundColor DarkGray
Write-Host "  MCP      http://localhost:5000/mcp   (wired in .vscode/mcp.json as 'wardgeneral-dab')" -ForegroundColor DarkGray
Write-Host "Ctrl+C to stop." -ForegroundColor DarkGray

dab start -c $Config
