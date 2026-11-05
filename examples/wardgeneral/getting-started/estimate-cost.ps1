# =============================================================================
# Ward General — Getting Started
# estimate-cost.ps1
#
# Print a LIVE, itemized monthly cost estimate for the deployed shape, pulled
# from the public Azure Retail Prices API (unauthenticated, read-only) at run
# time. The project teaches the pricing *model* and shows this *method*; the
# numbers you see are generated live for your region/shape — nothing is frozen
# in print (numbers age; the model does not).
#
# What it estimates (pay-as-you-go retail, USD) for the deployed Hyperscale
# shape:
#   * Compute  = vCore rate x vCores x (primary + HA replicas) x 730 hours
#   * Storage  = data-stored rate x allocated GB
#   * Backup   = redundancy rate x billable GB (only the excess beyond one
#                database size is billable; ~0 on a fresh deploy)
#
# Excludes: reservations / savings plans, egress, and any org discount. Azure
# Hybrid Benefit does not apply to new Hyperscale databases (no license fee).
#
# Repo convention: PowerShell for every script, `az` CLI for control-plane.
# Run in PowerShell 7+ (pwsh).
# =============================================================================

param(
    [string]$Loc              = ($env:LOC ?? 'eastus2'),
    [string]$Slo              = ($env:SLO ?? 'HS_Gen5_8'),
    [int]   $HaReplicas       = [int]($env:HA_REPLICAS ?? '1'),
    [string]$BackupRedundancy = ($env:BACKUP_REDUNDANCY ?? 'GeoZone'),
    [double]$AllocatedGB      = [double]($env:ALLOCATED_GB ?? '10')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$HoursPerMonth = 730

# --- Parse the SLO: HS_<series>_<vCores> (e.g. HS_Gen5_8, HS_PRMS_32) --------
if ($Slo -notmatch '^HS_([A-Za-z0-9]+)_(\d+)$') {
    throw "SLO '$Slo' is not a recognized Hyperscale service objective (expected HS_<series>_<vCores>)."
}
$series = $Matches[1]
$vCores = [int]$Matches[2]

# Map the series to the Retail Prices API product name for PROVISIONED compute.
$computeProduct = switch -Regex ($series) {
    '^Gen5$'   { 'SQL Database SingleDB/Elastic Pool Hyperscale - Compute Gen5' }
    '^Gen4$'   { 'SQL Database SingleDB Hyperscale - Compute Gen4' }
    '^PRMS$'   { 'SQL Database Single/Elastic Pool Hyperscale - Premium Series Compute' }
    '^MOPRMS$' { 'SQL Database Single/Elastic Pool Hyperscale - Premium Series Memory Optimized Compute' }
    default    { throw "Unrecognized Hyperscale series '$series' (SLO '$Slo'). Add its product mapping to estimate-cost.ps1." }
}

# Map backup redundancy to its Retail Prices skuName.
$backupSku = switch ($BackupRedundancy) {
    'Local'   { 'Backup - LRS' }
    'Zone'    { 'Backup - ZRS' }
    'Geo'     { 'Backup - RA-GRS' }
    'GeoZone' { 'Backup - RA-GZRS' }
    default   { throw "Unknown BACKUP_REDUNDANCY '$BackupRedundancy' (expected Local|Zone|Geo|GeoZone)." }
}

# --- Pull the region's SQL Database consumption meters (paged) ---------------
Write-Host "Querying Azure Retail Prices API for '$Loc' (live rates)..."
$filter = "serviceName eq 'SQL Database' and armRegionName eq '$Loc' and priceType eq 'Consumption'"
$uri = 'https://prices.azure.com/api/retail/prices?$filter=' + $filter
$items = @()
$next = $uri
do {
    $resp = Invoke-RestMethod -Uri $next
    $items += $resp.Items
    $next = $resp.NextPageLink
} while ($next)

function Get-Rate {
    param([string]$Product, [string]$Sku, [string]$Meter, [string]$Unit)
    $match = $items | Where-Object {
        $_.productName -eq $Product -and
        $_.unitOfMeasure -eq $Unit -and
        (-not $Sku   -or $_.skuName   -eq $Sku) -and
        (-not $Meter -or $_.meterName -eq $Meter) -and
        $_.productName -notmatch 'Serverless' -and
        $_.meterName   -notmatch 'Read Repl'
    } | Select-Object -First 1
    if (-not $match) { return $null }
    return [double]$match.retailPrice
}

# Compute (per vCore-hour), data storage (per GB/mo), backup (per GB/mo).
$computeRate = Get-Rate -Product $computeProduct -Meter 'vCore' -Unit '1 Hour'
$dataRate    = Get-Rate -Product 'SQL Database SingleDB Hyperscale - Storage' -Sku 'Hyperscale' -Meter 'Hyperscale Data Stored' -Unit '1 GB/Month'
$backupRate  = Get-Rate -Product 'SQL Database SingleDB Hyperscale - Storage' -Sku $backupSku -Unit '1 GB/Month'

if (-not $computeRate) { throw "Could not find a provisioned compute rate for '$computeProduct' in '$Loc'. The meter shape may have changed — re-check the Retail Prices API." }

$replicas       = 1 + $HaReplicas
$computeMonthly = $computeRate * $vCores * $replicas * $HoursPerMonth
$dataMonthly    = ($dataRate ?? 0) * $AllocatedGB
# Backup is billed only on the excess beyond one free database-size allowance;
# on a fresh deploy that excess is ~0, so we show the RATE, not a charge.
$estimatedTotal = $computeMonthly + $dataMonthly

$ci = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
function USD([double]$v) { '{0}' -f $v.ToString('C2', $ci) }

Write-Host ""
Write-Host "===== Estimated monthly cost (LIVE retail, USD, pay-as-you-go) ====="
Write-Host ("Region / shape : {0} / {1}  ({2} vCores x {3} replicas = {4} billed vCores)" -f $Loc, $Slo, $vCores, $replicas, ($vCores * $replicas))
Write-Host ""
Write-Host ("Compute        : {0,10}   ({1}/vCore-hr x {2} vCores x {3} replicas x {4} hr)" -f (USD $computeMonthly), (USD $computeRate), $vCores, $replicas, $HoursPerMonth)
Write-Host ("Data storage   : {0,10}   ({1}/GB-mo x {2:N0} GB allocated)" -f (USD $dataMonthly), (USD ($dataRate ?? 0)), $AllocatedGB)
if ($backupRate) {
    Write-Host ("Backup ({0,-7}): {1,10}/GB-mo   billed only on excess beyond one database size (~{2} on a fresh deploy)" -f $BackupRedundancy, (USD $backupRate), (USD 0))
}
Write-Host ("{0}" -f ('-' * 66))
Write-Host ("Est. total     : {0,10}  / month  (compute + storage; backup excess extra)" -f (USD $estimatedTotal))

# ----- Deploy-time cost levers (cost vs resilience tradeoffs) ----------------
# The biggest deploy-time savings come from the SAME choices that buy
# resilience. Show them as deltas so the tradeoff is explicit.
Write-Host ""
Write-Host "----- Deploy-time cost levers (cost vs resilience tradeoffs) -----"
if ($HaReplicas -ge 1) {
    $computeNoHa = $computeRate * $vCores * 1 * $HoursPerMonth
    $savePct = [int](100 * ($computeMonthly - $computeNoHa) / $computeMonthly)
    Write-Host ("  Hyperscale zone redundancy / HA: {0} HA replica(s) -> compute x{1} (per-replica billing)." -f $HaReplicas, (1 + $HaReplicas))
    Write-Host ("    Dropping to 0 HA / no zone redundancy cuts COMPUTE ~{0}%  ({1} -> {2})," -f $savePct, (USD $computeMonthly), (USD $computeNoHa))
    Write-Host  "    but you lose zone-failure survival (99.995 -> 99.99 SLA) and the hot standby's fast failover."
}
$zrsRate  = Get-Rate -Product 'SQL Database SingleDB Hyperscale - Storage' -Sku 'Backup - ZRS'    -Unit '1 GB/Month'
$gzrsRate = Get-Rate -Product 'SQL Database SingleDB Hyperscale - Storage' -Sku 'Backup - RA-GZRS' -Unit '1 GB/Month'
if ($zrsRate -and $gzrsRate -and $gzrsRate -gt 0) {
    $bkSavePct = [int](100 * ($gzrsRate - $zrsRate) / $gzrsRate)
    Write-Host ("  Backup redundancy: GeoZone {0}/GB vs Zone {1}/GB -> Zone is ~{2}% cheaper per backup GB," -f (USD $gzrsRate), (USD $zrsRate), $bkSavePct)
    Write-Host  "    but Zone drops cross-region geo-restore (Local is cheaper still; also drops zone protection)."
}
Write-Host  "  Rule of thumb: the resilience choices (zone redundancy + HA replica, GeoZone backup) ARE"
Write-Host  "  the cost. There's no free resilience -- trade it consciously against the workload's needs."

Write-Host ""
Write-Host "Notes:"
Write-Host "  * Compute dominates: it's per-REPLICA, so 1 HA replica doubles it."
Write-Host "  * Storage bills on ACTUAL allocation (10 GB min), growing as data grows."
Write-Host "  * Backup: only GB beyond one free database-size are billable; GeoZone"
Write-Host "    is ~2x Zone per GB (a second geographic copy), not a backup-method cost."
Write-Host "  * Excludes reservations / savings plans, egress, and org discounts."
Write-Host "  * For scenario modeling, use the Azure Pricing Calculator:"
Write-Host "    https://azure.microsoft.com/pricing/calculator/"
Write-Host ("  * Rates fetched live on {0} — numbers change; the model does not." -f (Get-Date -Format 'yyyy-MM-dd'))
