# Observability — Observe Hyperscale Availability

This walkthrough establishes current and recent availability evidence for the
Ward General Hospital Hyperscale database. It begins with Azure Resource Health,
reads the Hyperscale replica topology and synchronization evidence from SQL,
queries the previous 24 hours of Azure Monitor availability and connection
metrics, and then optionally asks Microsoft Copilot in Azure to summarize the
same evidence.

The deterministic portal and SQL results are the source of record. Copilot is
an optional assistant whose response must be checked against those results.

> **New here?** Read the [repository README](../../../README.md) first. This
> walkthrough assumes Getting Started has deployed `wardgeneral`.

## Files

| File | Purpose |
| --- | --- |
| `run-availability.ps1` | Loads Ward General configuration, resolves the database resource ID and region, verifies the new `sqlcmd`, runs the read-only SQL, and writes the previous 24 hours of Azure Monitor availability metrics to a temporary evidence directory. |
| `availability.sql` | Reports Hyperscale replica topology, synchronization evidence visible from the current connection, and current connection state. |

## Prerequisites

- Use the new Go-based `sqlcmd`, whose executable name is `sqlcmd`:

  ```powershell
  sqlcmd --version
  ```

  A successful command that prints `Version: v1...` confirms the new version.
  Install it with `winget install --id Microsoft.Sqlcmd` if needed.
- Sign in with `az login` so `sqlcmd -G` can use passwordless authentication.
- Configure the server in
  [`../../first-app/wardgeneral.env`](../../first-app/wardgeneral.env.template), set
  `WardGeneral__Server`, or supply the server explicitly.
- Connect with permission to read database state DMVs.
- Microsoft Copilot in Azure access is optional and may remain limited preview.

## Exact walkthrough

### 1. Establish Azure's resource assessment

The skill resolves the database with `az sql db show`; it does not assume a
region. It maps the returned region code, such as `centralus`, to Azure's
display name, such as `Central US`.

The skill then queries **Resource Health** for the exact database resource ID
and records its status and reported timestamp. It queries **Service Health**
for the current subscription and filters the results to both **Azure SQL
Database** and the derived region display name. A similarly named region does
not count. Do not infer replica synchronization from the absence of a platform
incident.

### 2. Run the SQL evidence

From the repository root, using the server configured in Ward General App:

```powershell
./observability/availability/run-availability.ps1
```

Or pass the server explicitly:

```powershell
./observability/availability/run-availability.ps1 `
  -Server '<your-server>.database.windows.net' `
  -Database 'wardgeneral'
```

The launcher calls the executable `sqlcmd` and uses `sqlcmd --version` to
reject the legacy ODBC implementation. Its opening lines print the subscription,
exact resource ID, and derived region used by the skill's health checks.

### 3. Interpret the result sets

The first result identifies the Hyperscale replica tree. Read
`replica_role_desc`, server and database names, locality, and parent replica ID.
It can include the primary, HA secondaries, named replicas, and geo secondaries.

The second result reports synchronization evidence returned to the current
connection. Keep `replica_id` so rows can be correlated with topology when the
identifiers align. A healthy observation commonly reports `SYNCHRONIZED`, but
describe the rows actually returned. Null health or database-state fields are
not automatically failures; Azure SQL does not populate every field for every
remote replica row.

The third result proves where this session connected, whether the database is
read-write or read-only, its current status, and the UTC sample time.

Continuous priming keeps eligible HA replicas warm, but neither
`sys.dm_hs_database_replicas` nor `sys.dm_database_replica_states` exposes a
direct priming-status column. Do not invent one or translate synchronization
state into priming state.

### 4. Read the Azure Monitor history

The launcher retrieves these Azure Monitor platform metrics for the previous
24 hours at one-minute granularity and writes the complete result to
`azure-monitor-availability.json`:

| Portal metric | REST API name | Aggregation and interpretation |
| --- | --- | --- |
| Availability | `availability` | Average and Minimum. Each minute is 100% unless all connection attempts fail because of system errors. No attempts, user errors, and firewall blocks do not reduce this metric. |
| Successful Connections | `connection_successful` | Total successfully established connections. |
| Failed Connections: System Errors | `connection_failed` | Total failures caused by internal Azure SQL service errors. |
| Failed Connections: User Errors | `connection_failed_user_error` | Total user-correctable failures, such as incorrect credentials. |
| Blocked by Firewall | `blocked_by_firewall` | Total firewall-blocked attempts, shown separately from the broader user-error category. |
| Replication lag (preview) | `replication_lag_seconds` | Average and Maximum seconds a secondary trails its primary. The metric is available on the primary and can split by replication partner. |

An empty series means **no metric values were returned**, not zero. Preserve
that distinction for user-error and replication-lag evidence. Availability is
connection-based historical evidence; it does not replace Resource Health or
prove replica synchronization. The replica DMVs remain the point-in-time
topology and synchronization sources.

The skill finishes with one structured assessment in the chat window; it does
not create a per-run Markdown report. The assessment identifies the resource
and derived region, gives each evidence source and UTC timestamp in a table,
details every replica, summarizes all six Azure Monitor metrics, and closes
with a conclusion and explicit limitations.
If the reader supplies Copilot output, the skill compares it separately with
the deterministic evidence.

The report is intentionally comparison-ready. It contains these sections in
order: completion and scope, authoritative baseline, 24-hour Azure Monitor
metrics, replica detail, conclusion and limitations, and the separate Copilot
prompt. When the reader returns Copilot's response, the agent adds a table with
one row per claim:

| Claim | Authoritative source | Observability baseline | Copilot response | Verdict |
| --- | --- | --- | --- | --- |

The comparison covers Resource Health, exact-region Service Health,
Availability, connection failures, firewall evidence, replica topology,
synchronization and lag, current connection, and the continuous-priming
visibility boundary. Each verdict is **Confirmed**, **Contradicted**,
**Missed**, or **Inconclusive**. Copilot does not override the baseline.

### 5. Optionally ask Microsoft Copilot in Azure

After preserving the portal and SQL evidence, ask:

```text
Assess the availability of wardgeneral over the last 24 hours.

Use available Azure health, monitoring, connection, and replica evidence.
Identify each source and its UTC timestamp. Clearly state when evidence is
unavailable or inconclusive.

Do not recommend or initiate failover, and do not change any resource.
```

Compare every claim with the Resource Health, Service Health, and SQL results.
Skip this step when Copilot access is unavailable or its output cannot be
independently verified.

## Boundaries

- Do not trigger a failover or change replica configuration to create evidence.
- Never hardcode the database region. Derive it from the Azure resource on each
  run and filter Service Health by the corresponding Azure display name.
- Resource Health is Azure's assessment of the resource, not replica topology.
- Synchronization evidence is a point-in-time observation, not an SLA report.
- High Availability and Resiliency owns failover mechanics, recovery objectives, and resiliency design.

## Live validation

The SQL was executed on 2026-08-30 against the 8-vCore Hyperscale
`wardgeneral` database using `sqlcmd` v1.10.0. It returned a primary, one HA
secondary, and the `wardgeneral-research` named replica. The synchronization
rows reported `SYNCHRONIZED`, the database reported `ONLINE`, and the current
connection reported `READ_WRITE`. These observations are not promised reader
results; topology and state depend on the deployment and sample time.

The 24-hour Azure Monitor query was validated on 2026-08-31. Availability was
100% in all 1,440 one-minute buckets. The period contained 26 successful
connections, zero system-error failures, and zero firewall blocks. Azure
Monitor returned no values for user-error failures or replication lag, which is
reported as unavailable rather than zero.

## Sources

Microsoft Learn, accessed 2026-08-30:

- [`sys.dm_hs_database_replicas`](https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-hs-database-replicas)
- [`sys.dm_database_replica_states`](https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-database-replica-states-transact-sql)
- [Hyperscale secondary replicas](https://learn.microsoft.com/azure/azure-sql/database/hyperscale-named-replica-overview)
- [Azure Resource Health overview](https://learn.microsoft.com/azure/service-health/resource-health-overview)
- [Microsoft Copilot in Azure for Azure SQL Database](https://learn.microsoft.com/azure/azure-sql/copilot/copilot-azure-sql-overview)
- [Azure SQL Database metrics and alerts](https://learn.microsoft.com/azure/azure-sql/database/monitoring-metrics-alerts)
