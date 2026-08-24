<#
.SYNOPSIS
    Shared configuration for the demo3 control-plane / Private Link demo.

.DESCRIPTION
    Dot-source this from every other script in this folder:

        . "$PSScriptRoot\00-config.ps1"

    This demo is SELF-CONTAINED. It creates its own VNet, logical server,
    database, and VM. It does not read from or write to anything owned by
    demo1_azureestate.

.NOTES
    THE SPLIT
      Control plane (az CLI) runs from the PRESENTER'S LAPTOP.
      Data plane (sqlsim) runs INSIDE THE VM.
      Those two never swap. The laptop never opens a SQL connection, and the
      VM never runs an az command.

    WHY THERE IS NO SQL ADMIN
      The logical server is created with --enable-ad-only-auth, so SQL
      authentication is off from birth and no password exists anywhere.

    WHY THE VM'S MANAGED IDENTITY IS THE ENTRA ADMIN
      The Entra admin may be a user, a group, or an application. Making it the
      VM's system-assigned identity means sqlsim can connect with
      -A ActiveDirectoryMsi as a full admin with no token, no CREATE USER, and
      nothing to expire. See:
      https://learn.microsoft.com/azure/azure-sql/database/authentication-azure-ad-only-authentication-create-server

    ONE AXIS, FIVE BEATS
      Everything from Beat 1 onward happens LIVE. Setup deliberately stops
      short of the private endpoint, the private DNS zone, and the DNS VNet
      link - those are Beats 2 and 5.
#>

$ErrorActionPreference = 'Stop'

# --- Azure ------------------------------------------------------------------
$script:SubscriptionId = '0efc44aa-c965-420f-aac4-fff305dbcc97'
$script:ResourceGroup  = 'bwsqlestaterg'
# The resource group lives in eastus; these resources deliberately do not.
$script:Location       = 'centralus'

# --- Azure SQL --------------------------------------------------------------
# Logical server names are globally unique DNS labels.
$script:ServerName   = 'bwpehyperscale-srv'
$script:DatabaseName = 'bwpehyperscale'
$script:ServerFqdn   = "$ServerName.database.windows.net"

# The name the Azure portal uses for "Allow Azure services and resources to
# access this server". Same name here so the audience recognizes it.
$script:AllowAzureRuleName = 'AllowAllWindowsAzureIps'

# --- Network ----------------------------------------------------------------
$script:VNetName       = 'vnet-demo3'
$script:VNetPrefix     = '10.42.0.0/16'
$script:DataSubnet     = 'snet-data'
$script:DataPrefix     = '10.42.1.0/24'
$script:ClientSubnet   = 'snet-client'
$script:ClientPrefix   = '10.42.2.0/24'
$script:NsgName        = 'nsg-demo3-client'
$script:RdpRuleName    = 'allow-rdp-presenter'
$script:DenyRuleName   = 'deny-all-inbound-internet'
$script:PeName         = 'pe-sql-demo3'
$script:PeConnection   = 'pec-sql-demo3'
$script:PrivateDnsZone = 'privatelink.database.windows.net'
$script:DnsLinkName    = 'link-vnet-demo3'
$script:DnsZoneGroup   = 'zg-sql-demo3'

# --- Client VM --------------------------------------------------------------
$script:VmName      = 'vm-demo3-client'
# Memory-optimized, the family you would actually pick for SQL Server on an
# Azure VM.
$script:VmSize      = 'Standard_E2s_v5'
$script:VmImage     = 'Win2022Datacenter'
$script:VmAdminUser = 'demoadmin'
$script:VmKitDir    = 'C:\demo'
$script:VmSqlSim    = "$VmKitDir\sqlsim.exe"

# --- Local paths ------------------------------------------------------------
$script:SqlSimLocal = 'C:\bwsql\sqlsimtools\sqlsim\build\x64\Release\sqlsim.exe'
$script:VmKitLocal  = Join-Path $PSScriptRoot 'vmkit'
$script:RdpFilePath = Join-Path $PSScriptRoot 'demo3.rdp'

# --- The query every beat runs ----------------------------------------------
# The database is empty on purpose. This query needs no schema and prints the
# connected principal, so the audience sees the managed identity by name.
$script:DemoQuery = 'SELECT DB_NAME() AS [Database], SUSER_SNAME() AS [ConnectedAs], CURRENT_TIMESTAMP AS [At]'

# --- Output helpers ---------------------------------------------------------
function Write-Step { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Skip { param([string]$Message) Write-Host "    $Message" -ForegroundColor DarkGray }
function Write-Warn { param([string]$Message) Write-Host "    $Message" -ForegroundColor Yellow }
function Write-Fail { param([string]$Message) Write-Host "    $Message" -ForegroundColor Red }

# Stage scripts echo the command before running it so the audience reads it too.
function Show-Command {
    param([string]$Command)
    Write-Host ''
    Write-Host "  $ $Command" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host ''
}

function Write-Beat {
    param([string]$Title)
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor Cyan
}

# az writes progress to stderr, which PowerShell surfaces as an error record.
# Gate on $LASTEXITCODE instead.
function Invoke-Az {
    param([string[]]$Arguments, [switch]$AllowFailure)

    $output = & az @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($AllowFailure) { return $null }

        # Never echo a secret. The value after --admin-password (and friends)
        # is redacted before the argument list reaches the error text.
        $secretFlags = @('--admin-password', '--password', '--client-secret', '--external-admin-sid')
        $safe = @()
        for ($i = 0; $i -lt $Arguments.Count; $i++) {
            $safe += $Arguments[$i]
            if ($secretFlags -contains $Arguments[$i] -and $i + 1 -lt $Arguments.Count) {
                $safe += '***REDACTED***'
                $i++
            }
        }
        throw "az $($safe -join ' ') failed with exit code $LASTEXITCODE`n$output"
    }

    # 2>&1 folds az's stderr warnings in as ErrorRecords. Only stdout is JSON.
    $stdout = $output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
    if ([string]::IsNullOrWhiteSpace($stdout)) { return $null }
    $parsed = ($stdout | Out-String | ConvertFrom-Json)

    # Some 'az ... show' commands (notably private-endpoint dns-zone-group show)
    # exit 0 and print '{}' when the resource does NOT exist. ConvertFrom-Json
    # turns that into a truthy PSCustomObject, so every 'if ($x) { skip }'
    # existence check silently reports "already exists" and skips the create.
    # Treat a property-less object as absent.
    if ($parsed -is [pscustomobject] -and @($parsed.PSObject.Properties).Count -eq 0) {
        return $null
    }
    return $parsed
}

function Get-MyPublicIp {
    try {
        return (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 15).Trim()
    }
    catch {
        throw "Could not detect this machine's public IP via api.ipify.org. $($_.Exception.Message)"
    }
}

# The VM's system-assigned identity, as both IDs. Azure SQL wants the
# application (client) ID when the Entra admin is an application.
function Get-VmIdentity {
    $principalId = & az vm show --resource-group $ResourceGroup --name $VmName `
        --query identity.principalId -o tsv 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($principalId)) {
        throw "VM '$VmName' has no system-assigned identity. Run 02-vm.ps1 first.`n$principalId"
    }
    $principalId = ($principalId | Out-String).Trim()

    $appId = & az ad sp show --id $principalId --query appId -o tsv 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($appId)) {
        throw "Could not resolve the application ID for principal $principalId.`n$appId"
    }

    return [pscustomobject]@{
        PrincipalId = $principalId
        AppId       = ($appId | Out-String).Trim()
    }
}

function Assert-SqlSimLocal {
    if (-not (Test-Path $SqlSimLocal)) {
        throw "sqlsim.exe not found at $SqlSimLocal"
    }
}

# Run a PowerShell script block inside the VM via ARM. Never touches the VNet,
# so it works from conference wifi even with public network access disabled.
function Invoke-VmScript {
    param([string]$Script)

    # Must go through a file. A multi-line string passed straight to --scripts
    # gets mangled by native argument quoting and the remote script silently
    # produces no output.
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "vmscript-$([guid]::NewGuid().ToString('N')).ps1"
    Set-Content -Path $tmp -Value $Script -Encoding UTF8

    try {
        $raw = & az vm run-command invoke `
            --resource-group $ResourceGroup `
            --name $VmName `
            --command-id RunPowerShellScript `
            --scripts "@$tmp" `
            -o json 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "az vm run-command invoke failed with exit code $LASTEXITCODE`n$raw"
        }

        $stdout = $raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
        $parsed = ($stdout | Out-String | ConvertFrom-Json)
        return (($parsed.value | ForEach-Object { $_.message }) -join "`n")
    }
    finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}
