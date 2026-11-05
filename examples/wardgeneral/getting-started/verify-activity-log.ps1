# =============================================================================
# Ward General — Getting Started
# verify-activity-log.ps1
#
# A THIRD way to verify the deployment — from the Azure control plane. Where
# connect-and-verify.sql proves the tier (it's SQL Server, it's Hyperscale) and
# verify-data.sql proves the data, this script summarizes the **Azure Activity
# Log** — the record of every control-plane operation ARM performed to build the
# database (create resource group, create server, set the Entra admin, add the
# firewall rule, create the Hyperscale database). If the deploy succeeded, you
# see a clean run of `Succeeded` events and no failures.
#
# Scope: the whole resource group (rg-collierhealth). In Getting Started that group holds
# only the SQL server + database + firewall rules, so RG scope IS the deploy.
# Scoping by resource group (not the server) keeps this independent of the
# globally-unique server name / random suffix. NOTE: the Activity Log filter
# allows time PLUS ONE scope only — you can't combine --resource-group with
# --namespace, so we filter by RG and read Microsoft.Sql events from it.
#
# Repo convention: PowerShell for every script, `az` CLI for control-plane.
# Run in PowerShell 7+ (pwsh). Read-only — creates and changes nothing.
#
# Inputs (env vars, sensible defaults):
#   RG         resource group            (default rg-collierhealth)
#   OFFSET     look-back window ##d##h   (default 6h; e.g. 1d, 12h, 2d)
#   MAX_EVENTS max records to pull       (default 200)
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Make native-command (az) non-zero exits throw, so a failed query stops here
# instead of silently returning nothing.
$PSNativeCommandUseErrorActionPreference = $true

$Rg     = $env:RG         ?? 'rg-collierhealth'
$Offset = $env:OFFSET     ?? '6h'
$Max    = [int]($env:MAX_EVENTS ?? '200')

# --- Confirm we're signed in (friendly message beats a raw az error) ---------
try   { $sub = az account show --query "{name:name, id:id}" -o json | ConvertFrom-Json }
catch { throw "Not signed in to Azure. Run 'az login' (and 'az account set -s <subscription>') first." }
Write-Host "Subscription : $($sub.name)  ($($sub.id))"
Write-Host "Resource grp : $Rg"
Write-Host "Window       : last $Offset`n"

# --- Pull the resource group's control-plane events over the window ----------
$raw = az monitor activity-log list `
    --resource-group $Rg `
    --offset $Offset `
    --max-events $Max `
    --query "[].{time:eventTimestamp, op:operationName.localizedValue, status:status.value, resId:resourceId, caller:caller}" `
    -o json | ConvertFrom-Json

$events = @($raw)
if ($events.Count -eq 0) {
    Write-Host "No Activity Log events for '$Rg' in the last $Offset." -ForegroundColor Yellow
    Write-Host "(Widen the window with `$env:OFFSET='1d', or confirm the resource group name.)"
    return
}

# Friendly resource name (last id segment) + newest first.
$events = $events | ForEach-Object {
    $_ | Add-Member -NotePropertyName resource -NotePropertyValue (($_.resId -split '/')[-1]) -PassThru
} | Sort-Object { [datetime]$_.time } -Descending

# --- Summary 1: events by status ---------------------------------------------
Write-Host "=== Events by status ==="
$events | Group-Object status | Sort-Object Count -Descending |
    Format-Table @{ n = 'Status'; e = { $_.Name } }, Count -AutoSize | Out-String | Write-Host

# --- Summary 2: events by operation ------------------------------------------
Write-Host "=== Events by operation ==="
$events | Group-Object op | Sort-Object Count -Descending |
    Format-Table @{ n = 'Operation'; e = { $_.Name } }, Count -AutoSize | Out-String | Write-Host

# --- Summary 3: most recent events -------------------------------------------
Write-Host "=== Most recent events (newest first) ==="
$events | Select-Object -First 25 `
    @{ n = 'Time (UTC)'; e = { ([datetime]$_.time).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') } },
    @{ n = 'Operation';  e = { $_.op } },
    @{ n = 'Status';     e = { $_.status } },
    @{ n = 'Resource';   e = { $_.resource } } |
    Format-Table -AutoSize | Out-String | Write-Host

# --- Flag any failures -------------------------------------------------------
$failed = $events | Where-Object { $_.status -in @('Failed', 'Error') }
if ($failed) {
    Write-Host "$($failed.Count) FAILED/error event(s) in the window:" -ForegroundColor Red
    $failed | Select-Object `
        @{ n = 'Time (UTC)'; e = { ([datetime]$_.time).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') } },
        @{ n = 'Operation'; e = { $_.op } }, @{ n = 'Resource'; e = { $_.resource } } |
        Format-Table -AutoSize | Out-String | Write-Host
    Write-Host "Investigate the failed operation(s) above before trusting the deploy." -ForegroundColor Red
}
else {
    Write-Host "No failed control-plane events in the window — the deploy operations all succeeded." -ForegroundColor Green
}
