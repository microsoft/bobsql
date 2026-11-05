# Pipeline upsert runs for 24 hours while tempdb grows

## Reported incident

A normally successful data-warehouse pipeline ran for approximately 24 hours
on a Saturday, tempdb became much larger, and the pipeline timed out. Similar
runs sometimes appear to become unexpectedly slow.

The report calls the pipeline "ADP"; the orchestration product and database
platform have not been confirmed. Do not assume this means Azure Data Factory
or that the warehouse runs on SQL Server rather than Synapse or Fabric.

**Working question:** what changed or stopped making progress, and what was
using tempdb during that interval?

Large tempdb files are an observation, not a root cause. Distinguish:

- Allocated file size from space currently occupied by objects.
- tempdb data-space pressure from tempdb log-space pressure.
- Growth caused by the slow workload from a resource constraint causing it.
- One database request running for 24 hours from pipeline retries, queueing,
  multiple batches, or waiting between requests.

## 1. Establish the environment and timeline

Collect these details before choosing platform-specific diagnostic scripts:

| Detail | Why it matters |
| --- | --- |
| Database product, version/build, edition/service tier, and compatibility level | SQL Server, Azure SQL, Synapse pools, and Fabric Warehouse expose different diagnostics and controls |
| Pipeline product and exact activity type | Copy/upsert, mapping data flow, stored procedure, and custom application paths behave differently |
| Exact error text/code and which timeout fired | Pipeline/activity timeout is not necessarily a SQL command timeout |
| Run/activity IDs, start/end timestamps, and time zone | Correlates orchestration history with database evidence; "last Saturday" is insufficient |
| Typical successful duration, row counts, source size, batch size, and concurrency | Establishes a comparable baseline |
| Retry history and overlapping/scheduled runs | Detects repeated work, load amplification, or concurrent upserts |
| Recent changes and Saturday maintenance | Includes source-data skew, duplicate keys, plans/statistics, indexes, deployments, backups, and other workloads |
| Upsert implementation and matching keys | Determines whether work stages data, scans a target, invokes a procedure, or uses another execution path |

Preserve the failing activity's input/output and integration-runtime metrics,
but redact connection strings, tokens, private endpoints, and business data.
Record the last successful run as well as the failed one.

## 2. Check whether the upsert stages data in tempdb

**Only if this is Azure Data Factory or Azure Synapse Copy activity targeting
Azure SQL Database:** inspect the sink's `writeBehavior` and
`upsertSettings.useTempDB`.

The [Azure SQL connector documentation](https://learn.microsoft.com/azure/data-factory/connector-azure-sql-database#azure-sql-database-as-the-sink)
states that upsert uses an interim table and that `useTempDB` defaults to
`true`, using a global temporary table. With `false`, the interim table is a
physical table in the user database.

This makes staging a concrete hypothesis, not proof of the incident's cause.
Determine whether the run was loading the interim table, applying changes to
the target, waiting on another transaction, or retrying.

Do not assume other connectors or pipeline activity types have the same
implementation. Do not immediately switch `useTempDB` off: that moves staging
work and requires appropriate user-database permissions and capacity. Test any
change with representative data and measure both staging and target-update work.

## 3. Capture evidence while the slowdown is happening

Start with read-only, platform-appropriate diagnostics. Have the database owner
confirm scope and required permissions. Take a normal-run baseline and repeated,
timestamped samples during the slow run rather than relying on one screenshot.

| Evidence | What to establish |
| --- | --- |
| tempdb data-file size, occupied space, and free space inside files | Whether files merely remain large after earlier activity or are actively filling |
| tempdb user objects, internal objects, and traditional version-store allocation | Whether staging/temp tables, worktables/spills, or row versions dominate |
| tempdb log use and transaction state | Whether the log, not data files, is the limiting resource |
| Storage/service-tier headroom and resource limits | Whether capacity or a managed-service limit was reached |
| Sessions and active requests mapped to the pipeline | Which request is running, waiting, blocked, or no longer present |
| Blocking chain and oldest transactions | Whether a blocked upsert or retained versions explain prolonged occupancy |
| Task/session tempdb allocations over time | Which work is allocating space; distinguish active tasks from completed-task accounting |
| Query progress, rows processed, CPU, reads/writes, and waits over time | Whether the same request is progressing or stalled |
| File IO deltas and growth events, where exposed | Whether storage latency or repeated autogrowth coincides with the slowdown |
| Plan/runtime history and safely obtainable execution evidence | Whether plans, cardinality estimates, memory grants, spills, or join access changed |

On SQL Server-family engines, relevant starting points include
`sys.dm_db_file_space_usage`, `sys.dm_db_task_space_usage`,
`sys.dm_db_session_space_usage`, and request/wait/transaction diagnostics.
These are not a portable script for every warehouse platform. Database scope,
permissions, and available views differ by product and version.

Keep allocation/deallocation and IO counters in context: many are cumulative,
so compare appropriately scoped samples and deltas. A current DMV snapshot
cannot reconstruct a run that already ended. Use retained monitoring, Query
Store where applicable, pipeline history, and existing event/error records for
the historical incident.

Version storage also depends on engine version, isolation, and ADR configuration.
Traditional tempdb version-store growth and a user database's ADR persistent
version store are different measurements; neither should be inferred solely
from the size of tempdb files.

## 4. Interpret the evidence before changing anything

| Observation | Investigate next |
| --- | --- |
| User-object allocation tracks staged input | Interim-table lifetime, input growth, batch size, concurrent runs, and the target-apply phase |
| Internal-object allocation and spill evidence increase | Sort/hash/spool work, plan changes, data skew, estimates, statistics, and memory-grant pressure |
| Version-store occupancy persists | Long-lived snapshot/read transactions and cleanup retention, using the platform's correct version-store diagnostics |
| Upsert is blocked while temp objects remain allocated | The head blocker and its transaction, not just the waiting pipeline session |
| Log occupancy increases | Active transactions and log reuse/throughput constraints |
| Growth events coincide with pauses or a capacity limit | File-growth configuration and storage/service-tier headroom, where configurable |
| `PAGELATCH_*` waits dominate | In-memory page contention and the specific resource; this is not itself proof of slow storage |
| `PAGEIOLATCH_*` or IO waits increase | Correlate actual IO latency, workload volume, and platform throttling; wait names alone do not prove a disk fault |
| No matching SQL request remains, but the activity is still running | Pipeline queueing, retries, source/transport delays, connection handling, and cancellation behavior |
| Allocated files stay large but current occupancy is low | Earlier growth and reusable free space; size alone does not establish an ongoing tempdb problem |

Treat these as branches to test, not diagnoses already established by the report.
Compare matching-key indexes, source/target row counts, data distribution, and
the successful versus slow execution path before deciding to tune the upsert.

## 5. Safe response and verification

- Preserve evidence before intervention. Do not start by shrinking tempdb,
  restarting SQL Server, clearing caches, killing sessions, or disabling
  isolation/ADR features.
- Increasing the timeout alone can prolong resource pressure without resolving
  the cause. Determine which operation stopped progressing first.
- Coordinate retries and cancellation with the pipeline owner. A timed-out
  activity does not prove all database work stopped; verify active requests and
  transaction state before replaying data.
- Review matching-key correctness and retry/idempotency behavior before reruns.
  Do not assume every failed run rolled back all earlier batches.
- If an operational intervention is necessary, have the owner approve its
  database, workload, data-consistency, and availability impact.
- Test one evidence-supported change at a time in a suitable environment.
  Compare duration, rows processed, peak tempdb occupancy, waits, IO, and errors
  against a comparable successful run.
- Afterward, verify request completion, expected committed data, transaction
  closure, and staging cleanup. Reusable file space may increase without the
  physical files shrinking.

## Handoff summary

Keep a redacted incident record containing:

1. Confirmed platform, activity type, target, and UTC timeline.
2. Exact timeout/error and run/activity identifiers.
3. Normal versus failing input, concurrency, retries, and duration.
4. Dominant tempdb allocation category, owning work, and blocking/wait evidence.
5. Evidence-supported cause or clearly labeled remaining hypotheses.
6. Approved intervention/change and measured verification results.

Do not attach raw production data or unredacted query text, plans, connection
settings, or notebook output to a public issue or this repository.

## References

- [tempdb database: contents, monitoring, and product differences](https://learn.microsoft.com/sql/relational-databases/databases/tempdb-database)
- [Azure SQL Database connector: Copy activity upsert behavior](https://learn.microsoft.com/azure/data-factory/connector-azure-sql-database)

Return to the [tempdb troubleshooting index](../readme.md).
