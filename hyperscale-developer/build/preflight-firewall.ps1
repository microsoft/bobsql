#requires -Version 7.0
<#
    Ward General — pre-flight: ensure THIS client's public IP is allowed through
    the Azure SQL server firewall.

    Why: the web app and Data API Builder both connect to
    collierhealth-17.database.windows.net with Active Directory Default. If the
    venue / hotel / conference public IP is not in the server firewall, every
    connection fails at login (SQL error 40615, "Client with IP address '...'
    is not allowed to access the server"). This detects the current public IP
    and — after asking — adds or updates a firewall rule for it.

    Read-only unless you confirm (or pass -Yes). Only touches ONE named rule;
    it never opens 0.0.0.0 / "all Azure services".

    ROTATING EGRESS (corpnet / NAT pools): on some networks (e.g. Microsoft
    corpnet 131.107.0.0/16) the OUTBOUND public IP rotates per connection, so
    the IP api.ipify.org reports is NOT the IP the server sees at login — a
    /32 rule fails with 40615 anyway. For those, authorize the whole egress
    range with -Cidr (e.g. -Cidr 131.107.0.0/16).

    Usage:
      ./preflight-firewall.ps1                       # detect IP, prompt, add/update a /32 rule
      ./preflight-firewall.ps1 -Yes                  # no prompt (rehearsal)
      ./preflight-firewall.ps1 -WhatIf               # show change, make none
      ./preflight-firewall.ps1 -Cidr 131.107.0.0/16  # authorize a whole egress range

    Returns exit code 0 when the client is (or becomes) allowed; non-zero on error.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Server = 'collierhealth-17',
    [string]$ResourceGroup = 'rg-collierhealth',
    [string]$RuleName,
    [string]$Cidr,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

function Convert-IpToUInt([string]$ip) {
    $b = ([System.Net.IPAddress]::Parse($ip)).GetAddressBytes()
    [Array]::Reverse($b)
    return [System.BitConverter]::ToUInt32($b, 0)
}

function Convert-CidrToRange([string]$cidr) {
    $parts = $cidr.Split('/')
    if ($parts.Count -ne 2) { throw "Invalid CIDR '$cidr' (expected a.b.c.d/nn)" }
    $prefix = [int]$parts[1]
    if ($prefix -lt 0 -or $prefix -gt 32) { throw "Invalid CIDR prefix '/$prefix'" }
    $base = Convert-IpToUInt $parts[0]
    $mask = if ($prefix -eq 0) { [uint32]0 } else { [uint32]((0xFFFFFFFFL -shl (32 - $prefix)) -band 0xFFFFFFFFL) }
    $lo = $base -band $mask
    $hi = $lo -bor ((-bnot $mask) -band 0xFFFFFFFFL)
    $toIp = { param($u) ([System.Net.IPAddress]::new([BitConverter]::GetBytes([uint32]$u)[3..0])).ToString() }
    return [pscustomobject]@{ Start = (& $toIp $lo); End = (& $toIp $hi) }
}

# -- az CLI present? ----------------------------------------------------------
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI (az) not found on PATH. Install it, then re-run. (Firewall rule NOT added.)"
    exit 2
}

# -- Logged in? ---------------------------------------------------------------
try {
    $acct = az account show -o json 2>$null | ConvertFrom-Json
    if (-not $acct) { throw 'no account' }
}
catch {
    Write-Error "Not logged in to Azure. Run 'az login' first. (Firewall rule NOT added.)"
    exit 3
}
Write-Host "Azure: $($acct.name) / $($acct.user.name)" -ForegroundColor DarkGray

# -- Determine the target IP range to authorize ------------------------------
# Default: the detected /32. With -Cidr: the whole egress range (for corpnet /
# NAT pools where the outbound IP rotates and a /32 can't work).
if ($Cidr) {
    try { $range = Convert-CidrToRange $Cidr }
    catch { Write-Error $_.Exception.Message; exit 4 }
    $startIp = $range.Start
    $endIp   = $range.End
    $label   = "$Cidr ($startIp-$endIp)"
    if (-not $RuleName) { $RuleName = "preflight-cidr-$($Cidr.Replace('/','_'))" }
    Write-Host "Target range: $label" -ForegroundColor Cyan
}
else {
    try {
        $myIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 10).Trim()
        $null = [System.Net.IPAddress]::Parse($myIp)
    }
    catch {
        Write-Error "Could not determine this client's public IP (https://api.ipify.org). Check your network. Details: $($_.Exception.Message)"
        exit 4
    }
    $startIp = $myIp
    $endIp   = $myIp
    $label   = $myIp
    if (-not $RuleName) { $RuleName = "preflight-$([System.Net.Dns]::GetHostName())" }
    Write-Host "This client's public IP: $myIp" -ForegroundColor Cyan
    Write-Host "Note: if this server rejects with 40615 despite this rule, your egress IP rotates (corpnet/NAT) — re-run with -Cidr to authorize the range." -ForegroundColor DarkGray
}

# -- Already allowed? (a rule must cover the ENTIRE target range) -------------
$rules = az sql server firewall-rule list --resource-group $ResourceGroup --server $Server -o json | ConvertFrom-Json
$tgtLo = Convert-IpToUInt $startIp
$tgtHi = Convert-IpToUInt $endIp
foreach ($r in $rules) {
    # Skip the "Allow Azure services" pseudo-rule (0.0.0.0-0.0.0.0).
    if ($r.startIpAddress -eq '0.0.0.0' -and $r.endIpAddress -eq '0.0.0.0') { continue }
    $lo = Convert-IpToUInt $r.startIpAddress
    $hi = Convert-IpToUInt $r.endIpAddress
    if ($tgtLo -ge $lo -and $tgtHi -le $hi) {
        Write-Host "OK: $label is already allowed by firewall rule '$($r.name)' ($($r.startIpAddress)-$($r.endIpAddress))." -ForegroundColor Green
        exit 0
    }
}

# -- Not allowed — confirm, then add/update our named rule --------------------
$existing = $rules | Where-Object { $_.name -eq $RuleName }
$action = if ($existing) { "UPDATE existing rule '$RuleName' ($($existing.startIpAddress)-$($existing.endIpAddress)) to $label" }
          else { "ADD rule '$RuleName' for $label" }

Write-Host ""
Write-Host "$label is NOT allowed on $Server." -ForegroundColor Yellow
Write-Host "Proposed change: $action on server '$Server' (resource group '$ResourceGroup')." -ForegroundColor Yellow

if (-not $Yes) {
    $answer = Read-Host "Add/update this firewall rule now? [y/N]"
    if ($answer -notmatch '^(y|yes)$') {
        Write-Warning "Skipped. The app/DAB will fail to connect until $label is allowed on $Server."
        exit 1
    }
}

if (-not $PSCmdlet.ShouldProcess("$Server / $RuleName", $action)) {
    exit 0
}

if ($existing) {
    az sql server firewall-rule update `
        --resource-group $ResourceGroup `
        --server $Server `
        --name $RuleName `
        --start-ip-address $startIp `
        --end-ip-address $endIp `
        -o table
}
else {
    az sql server firewall-rule create `
        --resource-group $ResourceGroup `
        --server $Server `
        --name $RuleName `
        --start-ip-address $startIp `
        --end-ip-address $endIp `
        -o table
}

Write-Host "Firewall rule '$RuleName' now allows $label on $Server." -ForegroundColor Green
exit 0
