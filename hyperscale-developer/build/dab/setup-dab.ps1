#requires -Version 7.0
<#
    Ward General — one-time setup for Data API Builder (DAB) + SQL MCP Server.

    Makes the DAB/MCP demo reproducible on a fresh machine or clone:
      1. Installs (or updates) the DAB CLI global tool.
      2. Deploys the two DAB-specific SQL objects to the database:
           - 08-research-vector-search.sql  (SearchSimilarNotes, text-only signature)
           - 11-dab-adapters.sql            (json boundary adapters for DAB)
         (The rest of the schema is deployed by the database deploy — see
          .github/skills/deploy-wardgeneral-db. These two are what DAB needs on
          top of a standard Ward General database.)
      3. Validates dab-config.json.

    Passwordless throughout (Microsoft Entra) — no secrets. Requires you to be
    signed in with the Azure CLI (az login) as a user who is a member of the
    database (or its Entra admin).

    Usage:
      ./setup-dab.ps1
      ./setup-dab.ps1 -Server myserver.database.windows.net -Database wardgeneral
      ./setup-dab.ps1 -SkipSql        # only ensure the CLI + validate config

    Then start it with:  ./run-dab.ps1
#>
[CmdletBinding()]
param(
    [string]$Server   = 'collierhealth-17.database.windows.net',
    [string]$Database = 'wardgeneral',
    [switch]$SkipSql
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
# SQL objects (08, 11) live in ../sql in the presentation kit, or co-located in a flat (book) folder.
$sqlDir = Join-Path $here '..' 'sql'
if (-not (Test-Path $sqlDir)) { $sqlDir = $here }
$config = Join-Path $here 'dab-config.json'

Write-Host "== Ward General DAB / SQL MCP setup ==" -ForegroundColor Cyan

# --- 1. DAB CLI --------------------------------------------------------------
if (Get-Command dab -ErrorAction SilentlyContinue) {
    Write-Host "DAB CLI present: $(dab --version)" -ForegroundColor Green
}
else {
    Write-Host "Installing DAB CLI (dotnet tool install -g Microsoft.DataApiBuilder)..." -ForegroundColor Yellow
    dotnet tool install --global Microsoft.DataApiBuilder
    if ($LASTEXITCODE -ne 0) { throw "DAB CLI install failed. Ensure the .NET SDK is installed." }
}

# --- 2. DAB-specific SQL -----------------------------------------------------
if (-not $SkipSql) {
    $scripts = @('08-research-vector-search.sql', '11-dab-adapters.sql')

    $sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
    if (-not $sqlcmd) {
        Write-Warning "sqlcmd not found — skipping SQL deploy. Install the SqlServer tools, or run these against $Database yourself:"
        $scripts | ForEach-Object { Write-Host "    sql/$_" -ForegroundColor DarkGray }
    }
    else {
        foreach ($s in $scripts) {
            $path = Join-Path $sqlDir $s
            if (-not (Test-Path $path)) { throw "Missing SQL script: $path" }
            Write-Host "Deploying $s ..." -ForegroundColor Yellow
            # -G = Microsoft Entra auth; uses your az login / interactive token.
            & sqlcmd -S $Server -d $Database -G -C -b -i $path
            if ($LASTEXITCODE -ne 0) { throw "Deploy failed for $s (exit $LASTEXITCODE)." }
        }
        Write-Host "SQL deployed." -ForegroundColor Green
    }
}

# --- 3. Validate config ------------------------------------------------------
$env:DAB_CONNECTION_STRING =
    "Server=tcp:$Server,1433;Database=$Database;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;"
Write-Host "Validating dab-config.json ..." -ForegroundColor Yellow
dab validate -c $config

Write-Host ""
Write-Host "Setup complete. Next:" -ForegroundColor Cyan
Write-Host "  1) Start the server:   ./run-dab.ps1" -ForegroundColor Gray
Write-Host "  2) In VS Code, MCP: List Servers -> start the SQL MCP Server (see README)." -ForegroundColor Gray
Write-Host "  3) Copilot (Agent mode): 'Find notes similar to elderly chest pain with elevated troponin.'" -ForegroundColor Gray
