#requires -Version 7.0
<#
    SQL MCP Server talk — build & run the DAB self-hosted process LOCALLY with MCP.

    Stands up the SQL MCP Server (Data API Builder) as a local process against the
    AdventureWorks database in the SQL Server 2025 container, exposing:
      REST     http://localhost:5000/api
      GraphQL  http://localhost:5000/graphql
      MCP      http://localhost:5000/mcp    <- wire this in .vscode/mcp.json

    Everything local, Windows integrated auth (your current login). This is the
    same config you'll ship to another laptop — only the connection string and
    auth provider change for cloud.

    Prereqs:
      - AdventureWorks restored into the local instance (./restore-adventureworks.ps1).
      - .NET SDK (for the DAB global tool).

    Usage:
      ./build.ps1                 # ensure CLI, validate config, start DAB
      ./build.ps1 -NoStart        # ensure CLI + validate only (don't start)
#>
[CmdletBinding()]
param(
    [string]$Server     = 'localhost',
    [string]$Database   = 'AdventureWorks',
    [int]$Port          = 5001,
    [string]$Config     = (Join-Path $PSScriptRoot 'dab/dab-config.json'),
    [switch]$NoStart
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Config)) { throw "DAB config not found: $Config" }

# --- 1. DAB CLI --------------------------------------------------------------
if (Get-Command dab -ErrorAction SilentlyContinue) {
    Write-Host "DAB CLI present: $(dab --version)" -ForegroundColor Green
}
else {
    Write-Host "Installing DAB CLI (dotnet tool install -g Microsoft.DataApiBuilder)..." -ForegroundColor Yellow
    dotnet tool install --global Microsoft.DataApiBuilder
    if ($LASTEXITCODE -ne 0) { throw "DAB CLI install failed. Ensure the .NET SDK is installed." }
}

# --- 2. Connection string (local Windows integrated auth) --------------------
# TrustServerCertificate=True because the local instance uses a self-signed cert.
$env:DAB_CONNECTION_STRING =
    "Server=$Server;Database=$Database;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;"

# Bind DAB to $Port (default 5001, so it can coexist with a Ward General DAB on 5000).
$env:ASPNETCORE_URLS = "http://localhost:$Port"

# --- 3. Validate config ------------------------------------------------------
Write-Host "Validating dab-config.json ..." -ForegroundColor Yellow
dab validate -c $Config
if ($LASTEXITCODE -ne 0) { throw "dab validate failed (exit $LASTEXITCODE)." }

if ($NoStart) {
    Write-Host "Config valid. -NoStart set; not starting DAB." -ForegroundColor Green
    return
}

# --- 4. Start ----------------------------------------------------------------
Write-Host ""
Write-Host "Starting SQL MCP Server (DAB) for $Database on $Server ..." -ForegroundColor Cyan
Write-Host "  REST     http://localhost:$Port/api" -ForegroundColor DarkGray
Write-Host "  GraphQL  http://localhost:$Port/graphql" -ForegroundColor DarkGray
Write-Host "  MCP      http://localhost:$Port/mcp   (wire in the workspace mcp.servers)" -ForegroundColor DarkGray
Write-Host "Ctrl+C to stop." -ForegroundColor DarkGray

dab start -c $Config
