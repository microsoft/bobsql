# =============================================================================
# Ward General — Getting Started §4 (Provision)
# add-replicas.ps1
#
# Add a second HA replica, then add a named replica. Show that they are
# different things: HA replicas are failover targets (and read-scale
# endpoints via ApplicationIntent=ReadOnly); named replicas are read-only
# scale-out objects that look like separate databases — never failover
# targets.
#
# Two realities the area wants to land (§4):
#   1. First-failover RTO depends on whether you pre-provisioned an HA
#      replica. With 0 HA replicas, the system must build one from scratch
#      on failover (slower). With >=1, the spare is hot. Forward-point High Availability and Resiliency.
#   2. Named replicas are NOT failover targets. The full HA-vs-named-vs-geo
#      comparison lives in Architecture §7.
#
# Hard constraint to flag here (Architecture §8 introduces, Performance §11 fills out):
# named replicas cannot live in a Hyperscale elastic pool.
#
# The replica created here is `wardgeneral-research`, and it is the one the
# rest of the project uses — Architecture §7 dissects it (sys.dm_hs_database_replicas
# proves it is genuinely its own database), and AI-Ready SQL is where it first does
# real work: the app's Research page runs vector search on it, so the
# read-heavy corpus search never touches the OLTP primary. Performance §8 covers
# scaling read-out further. Deploy it here so those areas have it.
#
# It is created SERVERLESS (HS_S_Gen5_8) on purpose: a research endpoint is
# idle between queries, and serverless AUTOSCALES compute (1-8 vCores here)
# with per-second billing, so the replica drops to its floor when nobody is
# researching. Be precise about what serverless does NOT do on Hyperscale
# today: it does NOT auto-pause to zero. Auto-pause/auto-resume ships on
# General Purpose serverless now, and is on the roadmap for Hyperscale
# serverless -- so as of August 2026 the replica idles at its minimum vCore,
# billing continuously. Note the other trade too -- continuous priming is
# provisioned-only (High Availability and Resiliency).
#
# Repo convention: PowerShell for every script, `az` CLI for Azure
# control-plane calls. Run in PowerShell 7+ (pwsh).
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$Rg  = $env:RG  ?? 'rg-collierhealth'
if (-not $env:SRV) { throw 'Set SRV to the logical server name (collierhealth-...).' }
$Srv = $env:SRV
$Db  = $env:DB  ?? 'wardgeneral'
$NamedReplica    = $env:NAMED_REPLICA     ?? 'wardgeneral-research'   # read-only scale-out endpoint
$NamedReplicaSlo = $env:NAMED_REPLICA_SLO ?? 'HS_S_Gen5_8'            # serverless: autoscales to a 1-vCore floor when idle (auto-pause not on Hyperscale yet)

Write-Host "--- Before ---"
az sql db show `
    --resource-group $Rg --server $Srv --name $Db `
    --query "{name:name, sku:currentServiceObjectiveName, ha:highAvailabilityReplicaCount}" `
    -o table

# ---------- 1. Add a second HA replica --------------------------------------
# HA replicas live "inside" the primary database object — there is no
# separate database resource. Increment the count.
Write-Host ""
Write-Host "--- 1/2 HA replica: increment to 2 ---"
az sql db update `
    --resource-group $Rg --server $Srv --name $Db `
    --ha-replicas 2 `
    -o table

Write-Host ""
Write-Host "Tip: connect with ApplicationIntent=ReadOnly to be routed to an HA replica."
Write-Host "Connection-string fragment:"
Write-Host "  Server=tcp:$Srv.database.windows.net,1433;Database=$Db;ApplicationIntent=ReadOnly;Authentication=Active Directory Default;Encrypt=true;"

# ---------- 2. Add a named replica ------------------------------------------
# Named replicas are created as a *new* database whose `createMode` is
# `Secondary` and whose source-database id points at the Hyperscale primary.
# `az sql db replica create` is the helper that wraps this; --secondary-type
# must be `Named` for a named replica (default `Geo`).
Write-Host ""
Write-Host "--- 2/2 Named replica: $NamedReplica ---"
az sql db replica create `
    --resource-group $Rg --server $Srv --name $Db `
    --partner-server $Srv --partner-database $NamedReplica `
    --secondary-type Named `
    --service-objective $NamedReplicaSlo `
    -o table

# ---------- Show what we have ----------------------------------------------
Write-Host ""
Write-Host "--- Replica list ---"
az sql db replica list-links `
    --resource-group $Rg --server $Srv --name $Db `
    -o table

Write-Host ""
Write-Host "--- Named replica details ---"
az sql db show `
    --resource-group $Rg --server $Srv --name $NamedReplica `
    --query "{name:name, sku:currentServiceObjectiveName, ha:highAvailabilityReplicaCount, state:status, secondaryType:secondaryType}" `
    -o table

@"

Notes (Getting Started §4):
  * Two endpoints in play:
      Primary  ->  $Srv.database.windows.net  (database: $Db)
                   Read/write, plus reroute via ApplicationIntent=ReadOnly
                   to an HA replica.
      Named    ->  $Srv.database.windows.net  (database: $NamedReplica)
                   Read-only. Looks like a separate database to clients.
                   NOT a failover target. Used by the app's Research page
                   from AI-Ready SQL on.
  * Each replica is its own compute meter (per-replica billing) — Getting Started §1
    pricing-model callout, in action. This one is serverless, so it bills
    per second on the compute it actually uses, dropping to its 1-vCore
    floor when idle. It does not pause: as of August 2026 auto-pause is a
    General Purpose feature, and is on the roadmap for Hyperscale.
  * Constraint to remember (planted here, expanded in Performance §11): named
    replicas cannot live in a Hyperscale elastic pool.
"@ | Write-Host
