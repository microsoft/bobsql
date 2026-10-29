#requires -Version 7.0
<#
    Ward General — one-time setup for Data API Builder (DAB) + SQL MCP Server.

    Makes the DAB/MCP demo reproducible on a fresh machine or clone:
      1. Installs (or updates) the DAB CLI global tool.
      2. Deploys the Agentic AI SQL objects to the database, in order:
         - 11-handoff-contract.sql        (AgentRecommendation + SaveShiftHandoff)
         - 12-handoff-candidates.sql      (GetHandoffCandidates)
         - 14-imaging-order-contract.sql  (ImagingOrder.RequestKey + PlaceImagingOrder,
                                           deployed but never called by the app)
         - 13-refresh-shift-window.sql    (re-anchor the shift window to now,
                                    and create genuinely outstanding labs)
         Run the scripts in the listed order so the deployed contracts match
         the DAB configuration used by the agent; the refresh runs last.
         (The rest of the schema comes from the database deploy - see
          .github/skills/deploy-hyperscale.)

         NOT deployed here: clinical.SearchSimilarNotes, which the
         search_clinical_context tool calls. That is AI-Ready SQL's
         09-research-vector-search.sql, and it is useless without the external
         model from 06 and the embeddings and vector index from 07 - none of
         which this script deploys either. Areas 4 and 5 are prerequisites;
         re-running one link of that chain would protect nothing.
      3. Validates dab-config.primary.json.

    Passwordless throughout (Microsoft Entra) — no secrets. Requires you to be
    signed in with the Azure CLI (az login) as a user who is a member of the
    database (or its Entra admin).

    Usage:
      ./setup-dab.ps1
      ./setup-dab.ps1 -Server contoso-sql-01.database.windows.net -Database wardgeneral
      ./setup-dab.ps1 -SkipSql        # only ensure the CLI + validate config
      ./setup-dab.ps1 -SqlCmd 'C:\path\to\go-sqlcmd\sqlcmd.exe'

    Then start it with:  ./run-dab.ps1
#>
[CmdletBinding()]
param(
    [string]$Server,
    [string]$Database,
    [switch]$SkipSql,
    [string]$SqlCmd
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

# Ward General App's env file is the one place the reader writes their server name.
$loadEnv = Join-Path $here '..' 'first-app' 'load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }

if (-not $Server)   { $Server   = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
if (-not $Server) {
    throw 'No server. Fill in WardGeneral__Server in first-app/wardgeneral.env, or pass -Server <your-server>.database.windows.net.'
}

# Agentic AI's scripts live beside this one. Some layouts collect everything
# under ../sql instead.
$sqlDirs = @(
    $here,
    (Join-Path $here '..' 'sql')
) | Where-Object { Test-Path $_ }
$config = Join-Path $here 'dab-config.primary.json'

Write-Host "== Ward General DAB / SQL MCP setup ==" -ForegroundColor Cyan

# --- 1. DAB CLI --------------------------------------------------------------
# 2.0 or later, not merely present: runtime.mcp and dml-tools do not exist in 1.x,
# where this config passes schema validation and then fails at startup with a JWT
# error that has nothing to do with the actual problem.
if (Get-Command dab -ErrorAction SilentlyContinue) {
    Write-Host "DAB CLI present: $(dab --version)" -ForegroundColor Green

    $dabVersion = (dab --version) -replace '^\D+', '' -replace '\+.*$', ''
    if ([version]($dabVersion -split '-')[0] -lt [version]'2.0.0') {
        Write-Host "DAB $dabVersion predates runtime.mcp. Updating to 2.x..." -ForegroundColor Yellow
        dotnet tool update --global Microsoft.DataApiBuilder
        if ($LASTEXITCODE -ne 0) { throw "DAB CLI update failed. Agentic AI requires 2.0.0 or later." }
    }
}
else {
    Write-Host "Installing DAB CLI (dotnet tool install -g Microsoft.DataApiBuilder)..." -ForegroundColor Yellow
    dotnet tool install --global Microsoft.DataApiBuilder
    if ($LASTEXITCODE -ne 0) { throw "DAB CLI install failed. Ensure the .NET SDK is installed." }
}

# --- 2. DAB-specific SQL -----------------------------------------------------
if (-not $SkipSql) {
    $scripts = @(
        '11-handoff-contract.sql',
        '12-handoff-candidates.sql',
        # Deployed but never called by the app — ordering plumbing the area
        # discusses rather than exposes. See the script header.
        '14-imaging-order-contract.sql',
        # Last on purpose: it re-anchors the demo window to the moment it runs, so
        # it has to follow anything that writes clinical rows.
        '13-refresh-shift-window.sql'
    )

    # go-sqlcmd, and specifically NOT the legacy ODBC sqlcmd. Both answer to the
    # name `sqlcmd` and both take -G, but -G means different things: go-sqlcmd with
    # no user/password uses DefaultAzureCredential - the same credential the app and
    # DAB use - while the ODBC build attempts interactive Entra auth and needs ODBC
    # 17.2+. Resolving by name alone is a trap, because the ODBC build installs to
    # the machine PATH, which Windows searches before the user PATH.
    $isGoSqlcmd = {
        param($exe)
        if (-not $exe) { return $false }
        # --version exists only in go-sqlcmd; the ODBC build rejects it.
        & $exe --version 2>&1 | Out-Null
        return $LASTEXITCODE -eq 0
    }

    $sqlcmdPath = @(
        $SqlCmd,
        $env:SQLCMD,
        (Join-Path $env:LOCALAPPDATA 'Programs\sqlcmd\sqlcmd.exe'),
        'C:\Program Files\sqlcmd\sqlcmd.exe',
        (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
    ) | Where-Object { $_ -and (Test-Path $_) -and (& $isGoSqlcmd $_) } | Select-Object -First 1

    # Fail, do not warn. Skipping the deploy leaves the reader with no Agentic AI
    # contracts and a setup script that claimed success - so the failure surfaces
    # later as an agent with missing tools, which looks like a model problem.
    if (-not $sqlcmdPath) {
        throw @"
go-sqlcmd not found - cannot deploy the Agentic AI SQL.

Agentic AI needs go-sqlcmd (sqlcmd v1.x), not the legacy ODBC sqlcmd. Only
go-sqlcmd's -G resolves DefaultAzureCredential, which is the same passwordless
identity the application and DAB already use.

  winget install --id Microsoft.Sqlcmd

No admin? Unzip the release and point at it:
  https://github.com/microsoft/go-sqlcmd/releases
  `$env:SQLCMD = 'C:\path\to\sqlcmd.exe'

Looked in: -SqlCmd, `$env:SQLCMD, %LOCALAPPDATA%\Programs\sqlcmd, C:\Program Files\sqlcmd, PATH.
If you have the ODBC sqlcmd on PATH it was skipped on purpose - `sqlcmd --version`
succeeds only on go-sqlcmd.

Or deploy these yourself against $Database and re-run with -SkipSql:
$($scripts | ForEach-Object { "    $_" } | Out-String)
"@
    }

    Write-Host "SQL runner: $sqlcmdPath" -ForegroundColor Green

    foreach ($s in $scripts) {
        $path = $sqlDirs | ForEach-Object { Join-Path $_ $s } |
                Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $path) { throw "Missing SQL script: $s (looked in $($sqlDirs -join ', '))" }
        Write-Host "Deploying $s ..." -ForegroundColor Yellow
        # -b so a failed batch sets the exit code; -C trusts the server cert.
        & $sqlcmdPath -S $Server -d $Database -G -C -b -i $path
        if ($LASTEXITCODE -ne 0) { throw "Deploy failed for $s (sqlcmd exit $LASTEXITCODE)." }
    }
    Write-Host "SQL deployed." -ForegroundColor Green
}

# --- 3. Validate config ------------------------------------------------------
$env:DAB_CONNECTION_STRING =
    "Server=tcp:$Server,1433;Database=$Database;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;"
Write-Host "Validating dab-config.primary.json ..." -ForegroundColor Yellow
dab validate -c $config

Write-Host ""
Write-Host "Setup complete. Next:" -ForegroundColor Cyan
Write-Host "  1) Start the endpoint:  ./run-dab.ps1" -ForegroundColor Gray
Write-Host "  2) Check the toolbox:   ./probe-mcp.ps1" -ForegroundColor Gray
Write-Host "  3) Start the app with Features:AiAgent on (see the README)." -ForegroundColor Gray
