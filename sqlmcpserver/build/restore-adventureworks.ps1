#requires -Version 7.0
<#
    SQL MCP Server talk — restore AdventureWorks into the LOCAL SQL Server 2025 instance.

    Windows integrated auth (your current login, which has sysadmin). No container,
    no sa password. Restores the downloaded AdventureWorks2022.bak as [AdventureWorks].

    The .bak is copied to the Public folder (C:\Users\Public) first so the SQL Server
    service account can read it regardless of where the repo lives; MOVE targets the
    instance's own default data directory (which the service account owns).

    Prereqs:
      - Local SQL Server 2025 instance reachable via Windows auth (default: localhost).
      - The .bak downloaded (./download-adventureworks.ps1).
      - sqlcmd on PATH.

    Usage:
      ./restore-adventureworks.ps1
      ./restore-adventureworks.ps1 -Server 'localhost' -Database AdventureWorks
#>
[CmdletBinding()]
param(
    [string]$Server      = 'localhost',
    [string]$BakPath     = (Join-Path $PSScriptRoot 'artifacts/AdventureWorks2022.bak'),
    [string]$Database    = 'AdventureWorks',
    [string]$DataLogical = 'AdventureWorks2022',
    [string]$LogLogical  = 'AdventureWorks2022_Log'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $BakPath)) {
    throw "Backup not found: $BakPath. Run ./download-adventureworks.ps1 first."
}
if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    throw "sqlcmd not found on PATH. Install the SqlServer command-line tools."
}

# --- 1. Instance default data directory (for MOVE targets) -------------------
$dataDir = (& sqlcmd -S $Server -E -C -h -1 -W -Q "SET NOCOUNT ON; SELECT CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS nvarchar(260));" |
    Where-Object { $_ -match '\S' } | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($dataDir)) { throw "Could not read InstanceDefaultDataPath from $Server." }
Write-Host "Instance data dir: $dataDir" -ForegroundColor Green

# --- 2. Stage the .bak where the service account can read it ------------------
$publicBak = Join-Path $env:PUBLIC 'AdventureWorks2022.bak'
Write-Host "Staging backup -> $publicBak ..." -ForegroundColor Cyan
Copy-Item $BakPath $publicBak -Force

# --- 3. Show the logical file names (informational) --------------------------
Write-Host "Reading backup file list ..." -ForegroundColor Cyan
& sqlcmd -S $Server -E -C -b -W -Q "SET NOCOUNT ON; RESTORE FILELISTONLY FROM DISK = N'$publicBak';" |
    Select-Object -First 12 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }

# --- 4. Restore --------------------------------------------------------------
$restore = @"
SET NOCOUNT ON;
IF DB_ID(N'$Database') IS NOT NULL
    ALTER DATABASE [$Database] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
RESTORE DATABASE [$Database]
FROM DISK = N'$publicBak'
WITH MOVE N'$DataLogical' TO N'$dataDir$Database.mdf',
     MOVE N'$LogLogical'  TO N'$dataDir${Database}_log.ldf',
     REPLACE, RECOVERY, STATS = 5;
ALTER DATABASE [$Database] SET MULTI_USER;
"@

Write-Host "Restoring [$Database] ..." -ForegroundColor Cyan
& sqlcmd -S $Server -E -C -b -Q $restore
if ($LASTEXITCODE -ne 0) { throw "RESTORE failed (exit $LASTEXITCODE). If MOVE names are wrong, check the file list above and pass -DataLogical / -LogLogical." }

# --- 5. Verify + tidy --------------------------------------------------------
& sqlcmd -S $Server -E -C -b -Q "SET NOCOUNT ON; SELECT COUNT(*) AS Products FROM [$Database].Production.Product;"
Remove-Item $publicBak -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "AdventureWorks restored as [$Database] on $Server." -ForegroundColor Green
Write-Host "Next: ./build.ps1   (starts DAB + SQL MCP Server for the cold-open demo)" -ForegroundColor Gray
