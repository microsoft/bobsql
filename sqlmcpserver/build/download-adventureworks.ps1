#requires -Version 7.0
<#
    SQL MCP Server talk — download the FULL AdventureWorks sample database.

    Pulls the official Microsoft AdventureWorks2022 OLTP backup (.bak) into
    build/artifacts/. This is the stock, public sample DB — nothing to redact.
    The restore script (restore-adventureworks.ps1) loads it into the local
    SQL Server 2025 container.

    Usage:
      ./download-adventureworks.ps1
      ./download-adventureworks.ps1 -Force        # re-download even if present
#>
[CmdletBinding()]
param(
    [string]$OutDir = (Join-Path $PSScriptRoot 'artifacts'),
    [string]$Url    = 'https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2022.bak',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

$dest = Join-Path $OutDir 'AdventureWorks2022.bak'

if ((Test-Path $dest) -and -not $Force) {
    $sizeMB = [math]::Round((Get-Item $dest).Length / 1MB, 1)
    Write-Host "Already downloaded: $dest ($sizeMB MB). Use -Force to re-download." -ForegroundColor Green
    return
}

Write-Host "Downloading AdventureWorks2022.bak ..." -ForegroundColor Cyan
Write-Host "  from $Url" -ForegroundColor DarkGray
Write-Host "  to   $dest" -ForegroundColor DarkGray

$sw = [System.Diagnostics.Stopwatch]::StartNew()

# Prefer curl.exe (fast, shows progress); fall back to Invoke-WebRequest.
$curl = Get-Command curl.exe -ErrorAction SilentlyContinue
if ($curl) {
    & curl.exe -L --fail -o $dest $Url
    if ($LASTEXITCODE -ne 0) { throw "curl download failed (exit $LASTEXITCODE)." }
}
else {
    try {
        Invoke-WebRequest -Uri $Url -OutFile $dest -MaximumRedirection 5
    }
    catch {
        throw "Download failed: $($_.Exception.Message)"
    }
}

$sw.Stop()

if (-not (Test-Path $dest)) { throw "Download produced no file at $dest." }
$sizeMB = [math]::Round((Get-Item $dest).Length / 1MB, 1)
if ($sizeMB -lt 10) {
    throw "Downloaded file is only $sizeMB MB — that's likely an HTML error page, not the .bak. Check the URL."
}

Write-Host "Downloaded $dest ($sizeMB MB) in $([math]::Round($sw.Elapsed.TotalSeconds,1))s." -ForegroundColor Green
Write-Host "Next: ./restore-adventureworks.ps1" -ForegroundColor Gray
