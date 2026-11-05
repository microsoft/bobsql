# Diagnose unexpected tempdb growth

## Problem to solve

tempdb data files or the transaction log grow beyond their normal size, possibly
accompanied by space pressure or a slow workload.

Determine **what is consuming or retaining tempdb space, whether the workload
is making progress, and whether tempdb pressure is a cause or a consequence
of the slowdown**. Large files alone do not establish a tempdb problem.

This pattern can occur with temporary tables, sort/hash spills, row version
retention, or long-running transactions.

## Diagnostic kit

The scripts support **SQL Server 2019+ and Azure SQL Managed Instance**.
They deliberately reject Azure SQL Database, Synapse, and Fabric; those products
need separate database-scoped diagnostics. Connect to **tempdb** before running
each script. No objects are created, data changed, or settings modified.

Use an account with access to tempdb and the required monitoring permissions:
`VIEW SERVER STATE` on SQL Server 2019; on SQL Server 2022+ the performance DMVs
require `VIEW SERVER PERFORMANCE STATE`. Managed Instance requirements vary with
the DMV and build; confirm the corresponding server-state/performance-state
permissions. Metadata visibility can require additional access. Arrange access
with the database owner rather than automatically granting it. Resolve permission
failures before interpreting results; restricted database visibility can omit
information.

| Order | Script | Results |
| --- | --- | --- |
| 1 | [01-space.sql](01-space.sql) | Build/start time, file size and growth settings, data allocation categories, log occupancy, and cumulative file IO |
| 2 | [02-consumers.sql](02-consumers.sql) | Net session allocations, deferred deallocation, active request allocations, progress counters, waits, and blockers |
| 3, for log pressure | [03-log-transactions.sql](03-log-transactions.sql) | Log reuse wait, transaction age and log bytes, plus separate session/request owner mappings |
| 4, for version retention | [04-version-store.sql](04-version-store.sql) | Traditional tempdb version space by source database, ADR/PVS configuration and size, and snapshot transaction candidates |

Run scripts in SSMS or VS Code, or use Windows authentication with sqlcmd:

```powershell
sqlcmd -S '<approved-instance>' -E -d tempdb -b -i '.\troubleshoot\tempdb\growth-and-slow-workloads\01-space.sql'
```

Repeat the relevant scripts every 30-60 seconds during an incident and compare
with a normal baseline. All result sets include a UTC sample timestamp; capture
is not an atomic snapshot. Transaction start and instance start timestamps are
labeled server-local. Store results privately, not in this repository.

### Reading the output

- File size is not occupied space. `free_extent_mb` is reusable space inside
  data files, not free disk capacity. Allocation categories do not account for
  every metadata page. Data-only fields are NULL for log files.
- `max_size_pages = -1` means no configured file limit, not unlimited storage;
  `0` means no growth. `growth_value` is pages unless `is_percent_growth = 1`,
  in which case it is percent. Managed Instance also has service limits.
- IO counters are cumulative. Average interval read latency is the delta in
  `io_stall_read_ms` divided by the delta in `num_of_reads` (likewise for writes).
  Do not divide by zero or compare counters across restarts/resets.
- Session usage combines completed-task counters with active tasks. Request
  usage shows only active tasks and overlaps session usage: **do not add the
  two result sets**. Parallel tasks are aggregated before joining to requests.
  Deferred deallocation and moving tasks make attribution approximate.
- Sleeping sessions can retain temporary objects or open transactions. Request
  results include other workloads so a blocker outside tempdb is still visible.
  Negative blocker IDs describe engine conditions, not killable session IDs.
- Request counters and session IDs need context: compare the same request over
  time and account for ID reuse. IO waits or memory grants alone do not prove
  spills; correlate with execution plans or retained runtime evidence.
- Transaction log-used/reserved bytes are per transaction, not total log
  occupancy. Owner mappings may repeat a transaction across requests or sessions;
  use the separate transaction result for totals.
- Traditional versions live in tempdb. ADR PVS normally lives in the source
  database; SQL Server 2025 can also enable ADR/PVS in tempdb. PVS output measures
  off-row versions, not all version storage. Snapshot transactions are retention
  candidates, not proof of the specific cause; secondary replicas can also
  affect cleanup.
- SQL text is off by default. Set `@include_sql_text = 1` in the consumers script
  only for an approved private capture; statements can contain secrets.

Invoke the workspace skill **`tempdb-growth`** to guide this workflow.

## 1. Establish scope and a baseline

Confirm the database product, version, and service tier before selecting
diagnostics. SQL Server, Azure SQL Database, Synapse pools, and Fabric Warehouse
do not expose identical views or controls.

Record:

- Normal and slow-run duration, input volume, batch size, and concurrency.
- Exact errors, timestamps, and which timeout fired.
- Recent workload, data, plan, statistics, or configuration changes.
- Retries, overlapping runs, and the database requests involved.

A job running for hours does not necessarily mean one SQL request ran for hours;
queueing, retries, and delays between requests can extend its elapsed time.

## 2. Separate file growth from active space pressure

Collect a normal-run baseline and repeated, timestamped samples during the
slowdown, using read-only diagnostics appropriate to the platform.

| Evidence | Question it answers |
| --- | --- |
| Data-file size, occupied space, and free space | Are files actively filling, or simply still large after earlier work? |
| User-object, internal-object, and version-store allocation | Are temporary tables, query workspaces, or retained row versions dominant? |
| tempdb log use and transaction state | Is the pressure in the log rather than the data files? |
| Task/session allocations and active requests | Which workload owns the space, and is its consumption increasing? |
| Blocking, oldest transactions, progress, and waits | Is work progressing, blocked, or retaining space while waiting? |
| IO deltas, growth events, and capacity/service limits | Does resource pressure coincide with the slowdown? |
| Plans, memory grants, and runtime history | Did execution change or start spilling? |

On SQL Server-family engines, starting points include
`sys.dm_db_file_space_usage`, `sys.dm_db_task_space_usage`,
`sys.dm_db_session_space_usage`, and request/wait/transaction diagnostics.
Confirm database scope, permissions, and availability for the product/version.
Compare deltas for cumulative counters rather than treating totals as current
activity.

Use retained monitoring, Query Store where applicable, and job history when the
incident has ended; a current DMV snapshot cannot reconstruct it. Identify where
row versions are stored for the engine and ADR configuration rather than assuming
all version retention consumes tempdb.

## 3. Follow the evidence to the cause

| Observation | Investigate |
| --- | --- |
| User objects dominate | Temporary/staging table size, lifetime, batch size, concurrency, and cleanup |
| Internal objects and spills increase | Sort/hash/spool work, plan changes, estimates, data skew, and memory grants |
| Version-store space remains occupied | Transactions retaining versions and cleanup progress in the relevant version store |
| Blocked work retains allocations | The head blocker and transaction lifetime |
| Log use rises | Active transactions and log reuse or throughput constraints |
| Growth pauses or capacity limits occur | Available headroom, growth settings where configurable, and workload demand |
| `PAGELATCH_*` waits dominate | The contended in-memory page/resource, not presumed slow storage |
| IO waits increase | Measured IO latency, workload volume, and platform throttling |
| No matching database request remains | Job queueing, retries, transport delays, or cancellation handling |
| Files are large but occupancy is low | Reusable free space from earlier growth, not necessarily an active incident |

These are hypotheses to test, not conclusions based on file size.

## 4. Resolve and verify

- Preserve evidence before shrinking files, restarting, killing sessions, or
  changing isolation/ADR settings. Obtain approval for disruptive interventions.
- Address the measured cause: for example, blocking, unnecessary staging,
  spilling execution plans, version retention, or insufficient resource headroom.
  Increasing a timeout alone does not resolve these problems.
- Before retrying timed-out work, verify active requests and transaction state.
  Confirm committed data and retry/idempotency behavior; a timeout does not prove
  that work stopped or that all earlier batches rolled back.
- Test one evidence-supported change at a time. Compare duration, rows processed,
  peak occupied space, waits, IO, and errors against a comparable normal run.
- Verify completion, expected data, transaction closure, and temporary-object
  cleanup. Successful space reuse does not require physical files to shrink.

Keep a redacted summary of the timeline, baseline, allocation owner, cause,
change, and verification results. Do not publish production data, credentials,
or unredacted query captures and plans.

## References

- [tempdb database: contents, monitoring, and product differences](https://learn.microsoft.com/sql/relational-databases/databases/tempdb-database)
- [Session space usage and completed-task accounting](https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-db-session-space-usage-transact-sql)
- [Database transactions and log usage](https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-tran-database-transactions-transact-sql)

Return to the [tempdb troubleshooting index](../readme.md).
