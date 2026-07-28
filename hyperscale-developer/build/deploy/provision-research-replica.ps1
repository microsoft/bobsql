<#
    Ward General Hospital — Hyperscale developer demo
    provision-research-replica.ps1 : add a read-only NAMED REPLICA for research /
                                     student vector search over historical notes.

    WHY (the Hyperscale story):
      A named replica gives research / student query load its OWN compute, over the
      SAME page-server storage as the OLTP primary — no data copy, no separate
      vector store, no ETL. Students run VECTOR_SEARCH over clinical.ClinicalNote
      embeddings on the replica; the primary keeps serving the ward with zero
      contention. Learn: "Dedicate one or more replicas exclusively to RAG
      retrieval workloads, keeping the primary compute free for transactional
      writes." (Hyperscale FAQ / secondary replicas, accessed 2026-07-20)

    ACCESS ISOLATION (recommended for the research angle):
      Put the named replica on a SEPARATE logical server and create student logins
      ONLY on that server. Their credentials never exist on the primary's server,
      so students can reach the replica and nothing else. (Learn: "Configure
      isolated access for Hyperscale named replicas".) Set -IsolationServer to a
      new server name to use this pattern; omit it to co-locate on the primary
      server (simpler; reuses the primary server's managed identity grant).

    COST: a named replica is billed as its own compute (per-replica billing). This
      script uses the SERVERLESS compute tier (autoscales 1-8 vCores by default,
      per-second billing) so the replica scales down to its floor when students are
      idle. NOTE: on Hyperscale, serverless AUTOSCALES but does NOT auto-pause to
      zero — auto-pause/resume is General Purpose only (Learn, accessed 2026-07-21),
      so it idles at the min vCore rather than pausing. Storage is NOT re-billed (it
      is shared with the primary). Drop it with 99-drop-research-replica.ps1 when done.

    All data is synthetic — no real PHI.
#>
[CmdletBinding()]
param(
    [string] $Rg               = 'rg-collierhealth',
    [string] $Server           = 'collierhealth-17',       # primary logical server
    [string] $Database         = 'wardgeneral',            # primary Hyperscale DB
    [string] $ReplicaName      = 'wardgeneral-research',   # named replica DB name
    [double] $MinVcore         = 1,                        # serverless autoscale FLOOR (idles here; no auto-pause on Hyperscale)
    [int]    $MaxVcore         = 8,                        # serverless autoscale CEILING
    [string] $IsolationServer  = '',                       # optional: separate server for student access isolation
    [int]    $HaReplicas       = 0                          # 0 = cheapest; 1 = add HA to the replica
)

$ErrorActionPreference = 'Stop'

# Named replicas must be in the SAME region as the primary. If an isolation server
# is requested, it must already exist (create it with az sql server create) in that
# region; this script does not create the server so the admin owns that decision.
$partnerServer = if ($IsolationServer) { $IsolationServer } else { $Server }

Write-Host "=== Creating Hyperscale named replica (serverless) ==="
Write-Host "  primary   : $Server/$Database"
Write-Host "  replica   : $partnerServer/$ReplicaName  (serverless Gen5, $MinVcore-$MaxVcore vCores, ha-replicas=$HaReplicas)"
Write-Host ""

$haArg = @()
if ($HaReplicas -gt 0) { $haArg = @('--ha-replicas', $HaReplicas) }

# Verified syntax — Learn "Configure and manage Hyperscale named replicas" +
# "Serverless compute tier" (accessed 2026-07-21). Serverless is set with
# --compute-model Serverless --family Gen5 --min-capacity <floor> --capacity <ceiling>.
# On Hyperscale, each named replica autoscales INDEPENDENTLY of the primary.
az sql db replica create `
    --resource-group $Rg `
    --name $Database `
    --server $Server `
    --secondary-type named `
    --partner-database $ReplicaName `
    --partner-server $partnerServer `
    --compute-model Serverless `
    --family Gen5 `
    --min-capacity $MinVcore `
    --capacity $MaxVcore `
    @haArg | Out-Null

Write-Host "--- Replica summary ---"
az sql db show `
    --resource-group $Rg `
    --server $partnerServer `
    --name $ReplicaName `
    --query "{name:name, server:'$partnerServer', slo:currentServiceObjectiveName, minVcore:minCapacity, status:status}" `
    -o table

@"

Done. The named replica reads from the SAME page servers as the primary — no data
was copied, and storage is not re-billed.

Next:
  1. Create the in-engine research surface (run against the PRIMARY):
       ../sql/08-research-vector-search.sql
     It creates clinical.SearchSimilarNotes (retrieval-only vector search) and a
     'research_reader' role. Because it runs on the primary, it is visible and
     callable on the read-only replica.

  2. Grant a student read-only access (access isolation):
       - Create the student LOGIN on $partnerServer only (master DB).
       - Create the matching USER in $Database (primary) and add to research_reader.
     See 08-research-vector-search.sql for the exact T-SQL.

  3. Connect students to the REPLICA using its own connection string:
       Server=$partnerServer.database.windows.net; Database=$ReplicaName
     (No ApplicationIntent needed — named replicas are always read-only.)

Cost note: this replica bills as its own compute until dropped. Tear down with
  99-drop-research-replica.ps1  (or: az sql db delete -g $Rg -s $partnerServer -n $ReplicaName).
"@ | Write-Host
