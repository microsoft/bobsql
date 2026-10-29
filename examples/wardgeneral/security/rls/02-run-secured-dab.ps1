<#
.SYNOPSIS
    Start the Agentic AI DAB endpoint with Security identity forwarding enabled.

.DESCRIPTION
    Reads the already-built Agentic AI DAB configuration, changes only the
    Security security boundary, writes a generated configuration under _local,
    validates it, and starts DAB visibly in the foreground. Ctrl+C stops DAB.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $Server,
    [string] $Database,
    [int] $Port = 5000,
    [switch] $PrepareOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

if (-not (Get-Command dab -ErrorAction SilentlyContinue)) {
    throw 'DAB CLI not found. Areas 4–6 are prerequisites; restore their toolchain before running Security.'
}

$loadEnv = Join-Path $here '..' '..' 'first-app' 'load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }
if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') {
    throw 'No server. Fill in WardGeneral__Server in first-app/wardgeneral.env, set the environment variable, or pass -Server explicitly.'
}

$area6Config = Join-Path $here '..' '..' 'agentic-ai' 'dab-config.primary.json'
if (-not (Test-Path $area6Config)) {
    throw "Agentic AI DAB configuration not found: $area6Config"
}

$config = Get-Content -LiteralPath $area6Config -Raw | ConvertFrom-Json -Depth 100
$config.'data-source' | Add-Member -NotePropertyName options -NotePropertyValue @{
    'set-session-context' = $true
} -Force
$config.runtime.host.authentication = @{ provider = 'AppService' }

foreach ($entity in $config.entities.PSObject.Properties.Value) {
    foreach ($permission in $entity.permissions) {
        if ($permission.role -eq 'anonymous') { $permission.role = 'authenticated' }
    }
}

$local = Join-Path $here '_local'
New-Item -ItemType Directory -Path $local -Force | Out-Null
$generatedConfig = Join-Path $local 'dab-config.rls.json'
$config | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $generatedConfig -Encoding utf8

$env:DAB_CONNECTION_STRING =
    "Server=tcp:$Server,1433;Database=$Database;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;"
$env:ASPNETCORE_URLS = "http://localhost:$Port"
if (-not $env:AZURE_TOKEN_CREDENTIALS) {
    $env:AZURE_TOKEN_CREDENTIALS = 'AzureCliCredential'
}

Write-Host 'Validating the generated Security DAB configuration ...' -ForegroundColor DarkGray
dab validate -c $generatedConfig
if ($LASTEXITCODE -ne 0) { throw 'Security DAB configuration validation failed.' }

if ($PrepareOnly) {
    Write-Output $generatedConfig
    return
}

Write-Host ''
Write-Host 'Data API Builder — Security secured MCP endpoint' -ForegroundColor Cyan
Write-Host "  database  $Database on $Server" -ForegroundColor DarkGray
Write-Host '  auth      AppService header simulation (localhost only)' -ForegroundColor DarkGray
Write-Host '  claims    forwarded to SQL SESSION_CONTEXT' -ForegroundColor DarkGray
Write-Host "  MCP       http://localhost:$Port/mcp" -ForegroundColor DarkGray
Write-Host ''
Write-Host 'Leave this terminal open. Press Ctrl+C to stop DAB.' -ForegroundColor DarkGray

dab start -c $generatedConfig --no-https-redirect
