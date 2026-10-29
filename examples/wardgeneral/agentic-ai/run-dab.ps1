#requires -Version 7.0
<#
.SYNOPSIS
    Ward General - start the Data API Builder (DAB) endpoint locally.

.DESCRIPTION
    One DAB process, on port 5000, against the wardgeneral PRIMARY. It publishes
    the agent's whole toolbox: current chart reads, the shift-handoff candidate
    roster, historical similarity search, and the approval-gated save_handoff.

    A DAB configuration carries exactly one connection string, so one process
    reaches one database - and the database the agent talks to is the primary.
    The AI-Ready SQL Research page reaches the named replica on its own ADO.NET
    connection (WardGeneralConnectionFactory.CreateResearch), not through DAB.

    Passwordless throughout: 'Active Directory Default' picks up your az login /
    VS Code / Azure identity. There is no secret in this file or in the config.
    In Azure this belongs in Container Apps with a managed identity.

    Ctrl+C stops it.

.PARAMETER Server
    Logical server FQDN. Defaults to WardGeneral__Server, which wardgeneral.env sets.
    There is deliberately no built-in server name: a default resource name is
    always somebody else's environment.

.PARAMETER Database
    Defaults to WardGeneral__Database, then to wardgeneral.

.EXAMPLE
    ./run-dab.ps1

.EXAMPLE
    ./run-dab.ps1 -Server contoso-sql-01.database.windows.net
#>
[CmdletBinding()]
param(
    [string]$Server,
    [string]$Database,
    [int]   $Port = 5000,
    [string]$Config
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command dab -ErrorAction SilentlyContinue)) {
    throw "DAB CLI not found. Install it with:  dotnet tool install --global Microsoft.DataApiBuilder"
}

# runtime.mcp (and dml-tools with it) arrived in DAB 2.0. On 1.x the config still
# passes schema validation, then the engine dies with "Audience and Issuer must be
# set when using a JWT identity Provider" against a config that plainly says
# Unauthenticated - an error that points nowhere near the real cause. Fail here
# with the version instead.
$dabVersion = (dab --version) -replace '^\D+', '' -replace '\+.*$', ''
if ([version]($dabVersion -split '-')[0] -lt [version]'2.0.0') {
    throw @"
DAB $dabVersion is too old. Agentic AI needs 2.0.0 or later, because runtime.mcp
and its dml-tools switch do not exist before 2.0 - and dml-tools is what bounds
the agent's tool surface to the eight entities in the config.

  dotnet tool update --global Microsoft.DataApiBuilder
"@
}

# Ward General App's env file is the one place the reader writes their server name, so
# read it rather than asking for it again. -Optional means an absent file is
# fine - the reader may be passing -Server instead.
$loadEnv = Join-Path $PSScriptRoot '..' 'first-app' 'load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }

if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Server) {
    throw 'No server. Fill in WardGeneral__Server in first-app/wardgeneral.env, or pass -Server <your-server>.database.windows.net.'
}
if ($Server -like '*<*') {
    throw "WardGeneral__Server is still a placeholder ($Server). Fill in first-app/wardgeneral.env."
}

if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
if (-not $Config)   { $Config   = Join-Path $PSScriptRoot 'dab-config.primary.json' }

if (-not (Test-Path $Config)) { throw "DAB config not found: $Config" }

# Fail before starting rather than after: dab reports a config problem clearly,
# and doing it here means a typo never reaches a half-started endpoint.
Write-Host "Validating $(Split-Path $Config -Leaf) ..." -ForegroundColor DarkGray

$env:DAB_CONNECTION_STRING =
    "Server=tcp:$Server,1433;Database=$Database;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;"

# This local launcher requires az login. Avoid spending DAB's startup window on
# unavailable managed-identity, IDE, PowerShell, and broker credentials first.
if (-not $env:AZURE_TOKEN_CREDENTIALS) {
    $env:AZURE_TOKEN_CREDENTIALS = 'AzureCliCredential'
}

dab validate -c $Config

# `dab start` has no port switch - DAB is an ASP.NET Core host, so the port comes
# from ASPNETCORE_URLS. HTTP only, and --no-https-redirect below, because this
# endpoint never leaves localhost in the project; in Azure it sits behind TLS.
$env:ASPNETCORE_URLS = "http://localhost:$Port"

Write-Host ''
Write-Host 'Data API Builder - Ward General primary' -ForegroundColor Cyan
Write-Host "  database   $Database on $Server"        -ForegroundColor DarkGray
Write-Host "  config     $(Split-Path $Config -Leaf)" -ForegroundColor DarkGray
Write-Host "  REST       http://localhost:$Port/api"  -ForegroundColor DarkGray
Write-Host "  MCP        http://localhost:$Port/mcp"  -ForegroundColor DarkGray
Write-Host ''
Write-Host 'Leave this running and start the app in a second terminal.' -ForegroundColor DarkGray
Write-Host "Probe the tool inventory with:  ./probe-mcp.ps1 -Port $Port" -ForegroundColor DarkGray
Write-Host 'Ctrl+C to stop.' -ForegroundColor DarkGray
Write-Host ''

dab start -c $Config --no-https-redirect
