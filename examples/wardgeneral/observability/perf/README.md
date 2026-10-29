# Observability — Observability, Monitoring, and Troubleshooting

This folder begins the Observability outside-in investigation against the Ward
General Hospital Hyperscale database. Azure Monitor first shows an idle database
and then a short CPU spike. The orchestrator removes clean pages from the buffer
pool, then three concurrent, read-only queries create that interval. SQL
statistics, `sys.dm_db_resource_stats`, virtual-file counters, and Query Store
show which statement did the work and whether RBPEX, page servers, or both
served the data pages.

The example diagnoses an anti-pattern. It does not create an index, scale the
database, clear RBPEX, fail over, or change data. It does remove clean pages
from the buffer pool, which can temporarily affect other users. Never run this
demo against production. Performance owns remediation.

> **New here?** Read the [repository README](../../../README.md) first. These files
> assume Getting Started has deployed and seeded `wardgeneral`, including the roughly
> 108 million rows in `clinical.Observation`.

## Files

| File | Purpose |
| --- | --- |
| `run-performance-demo.ps1` | Runs the complete investigation: snapshots RBPEX and page-server counters, removes clean buffer-pool pages, launches three concurrent scans, runs the database drill-down, retrieves Azure Monitor metrics, and writes consolidated evidence. This is the reader-facing entry point. |
| `observe-scan.sql` | The bounded anti-pattern. It scans `clinical.Observation` through the unindexed `ValueNumeric` predicate, returns four aggregate rows, and enables `STATISTICS IO` and `STATISTICS TIME`. |
| `run-concurrent-scans.ps1` | Starts exactly three concurrent new sqlcmd sessions, captures each session separately, and prints CPU, elapsed time, logical reads, page-server reads, page-server read-ahead, and the UTC investigation window. |
| `performance-drilldown.sql` | Correlates recent 15-second resource samples with the marked statement in Query Store, then reads the missing-index recommendation stored in that Query Store plan without applying it. |

The availability walkthrough is a sibling folder. Control-plane callbacks and
other supporting examples remain inline in the area rather than becoming
additional packaged workflows. Security owns SQL auditing and Defender for SQL.

## Reader prompt

From VS Code Chat in the repository workspace, enter:

```text
Run the Observability performance demo for wardgeneral.
```

That explicit request authorizes the bounded workload and its buffer-pool reset.
The agent should not ask for a second approval or ask the reader to predict
which lower cache tier will serve the pages. It runs the single orchestrator
below and reports the findings from the generated evidence.

## Prerequisites

- Complete Getting Started through `05-seed.sql`.
- Use PowerShell 7 or later.
- Install the **new Go-based sqlcmd**, not the legacy ODBC sqlcmd:

  ```powershell
  winget install --id Microsoft.Sqlcmd
  ```

- Install Azure CLI and sign in with `az login`. The same passwordless identity
  connects through the new sqlcmd's `-G` authentication and retrieves actual
  Azure Monitor metric values.
- Connect as the Getting Started administrator, or use a principal with permission to
  read Query Store and database state.
- Configure the server once in
  [`../../first-app/wardgeneral.env`](../../first-app/wardgeneral.env.template), or set it
  for the current PowerShell process:

  ```powershell
  $env:WardGeneral__Server = '<your-server>.database.windows.net'
  $env:WardGeneral__Database = 'wardgeneral'
  ```

## Controlled cache assumption

The scenario assumes the observation pages are clean. The orchestrator runs
`DBCC DROPCLEANBUFFERS` to remove clean pages from the in-memory buffer pool; it
does not issue `CHECKPOINT` first and does not clear RBPEX. The next scan must
retrieve each removed page from RBPEX where it is cached and from a page server
where it is absent. The result can therefore be RBPEX reads, page-server reads,
or both. The workflow measures the split instead of predicting it.

This is a buffer-pool reset, not a claim that the entire Hyperscale compute
cache is cold. It cannot guarantee page-server reads because RBPEX might already
contain the whole table. A nonzero page-server delta is the proof that the run
crossed that boundary; a zero page-server delta with nonzero RBPEX reads proves
that RBPEX served the lower-tier reads.

Either lower-tier signal can be zero on a particular run. What matters is that
the report names the observed path instead of assuming one:

| Outcome | Observed counters | Meaning |
| --- | --- | --- |
| RBPEX only | RBPEX delta greater than zero; page-server delta zero | The removed pages needed by the scan were available in the compute replica's local SSD cache. |
| Page server only | RBPEX delta zero; page-server delta greater than zero | The measured lower-tier reads came from page servers rather than RBPEX. |
| Mixed | Both deltas greater than zero | Some required pages were in RBPEX and others were fetched from page servers. |
| Neither | Both deltas zero | Do not infer a source. Check that clean pages were actually removed, inspect the per-session output, and account for concurrent activity. |

The console and `run-summary.json` show `RbpexVirtualFileDelta` and
`PageServerVirtualFileDelta`, each with reads, bytes read, and read-stall
milliseconds. The three `session-*.txt` files separately show statement-level
`page server reads` and `page server read-ahead reads` from `STATISTICS IO`.
Azure Monitor **Data IO percentage** can show local SSD pressure, but it does
not identify RBPEX reads and does not count page-server reads.

High Availability and Resiliency owns HA and failover behavior, not read scale. Performance owns
named-replica read scale and can create a new named replica for a separate
first-touch demonstration. A
named replica has independent compute caches and does not benefit from
continuous priming, so Performance can measure its initial page-server activity,
repeat the query to show cache warming, and then remove the replica. Even there,
the counters remain the proof; the text should not promise an exact read count.

## Exact walkthrough

### 1. Run the investigation

From the repository root, run one command:

```powershell
./observability/perf/run-performance-demo.ps1
```

That one orchestrator validates the prerequisites, snapshots RBPEX and
page-server counters, removes clean buffer-pool pages, launches exactly three
concurrent read-only scans, preserves the UTC interval, runs the SQL drill-down,
retrieves the corresponding Azure Monitor metrics, and writes all raw evidence
plus `run-summary.json` to one timestamped temporary directory.

It reports the measured RBPEX and page-server deltas. It does not call the
compute cache cold or claim page-server activity unless the counters prove it.

### 2. Receive the agent report

When this scenario is invoked through GitHub Copilot in VS Code, the agent
returns a self-contained report rather than only pointing at output files. The
report uses the current run's evidence and presents these sections in order:

1. Completion status and UTC investigation window.
2. A per-session table of CPU time, elapsed time, logical reads, page-server
  reads, and page-server read-ahead.
3. Peak 15-second `sys.dm_db_resource_stats` values and the corresponding Azure
  Monitor Average and Maximum values.
4. RBPEX and page-server virtual-file deltas, plus an RBPEX only, page server
  only, Mixed, or Neither classification.
5. Query Store executions, total CPU, duration, and logical reads.
6. The missing-index element from the plan stored in Query Store.
7. The evidence-backed diagnosis and Performance handoff.

The agent must not reuse the validation values later in this README as though
they came from the reader's run. If Azure Monitor has not yet published the
workload minute, it reports **not yet published** and preserves the UTC window;
it does not present unpublished zeros as the workload result or rerun the scan.
The report ends with the evidence-directory path for inspection.

### 3. Read the consolidated evidence

For each session, the summary reports:

- `LogicalReads` shows the roughly 1.1 million 8-KB pages the query touched.
- `PageServerReads` shows synchronous remote reads.
- `PageServerReadAhead` shows asynchronous remote read-ahead. This can carry
  nearly all the page-server traffic while `PageServerReads` remains zero.
- `QueryCpuMs` and `QueryElapsedMs` show the cost and the concurrency slowdown.

At least one nonzero page-server column establishes that the first-touch scan
crossed the compute-cache boundary. Zero across all sessions means the data was
already resident locally. Do not translate either page-server column into
`RBIO_*`: those are log-governance waits, not remote-read counters.

The drill-down output adds the recent 15-second resource samples, Query Store
execution statistics, and the `ValueNumeric` missing-index recommendation
stored in the Query Store plan. The summary reports two before-and-after
`sys.dm_io_virtual_file_stats()` deltas: `database_id = 0` rows show RBPEX reads,
while the current database's data-file rows show page-server reads. Each delta
includes reads, bytes, and read-stall time. Because the counters are
database-wide, unrelated concurrent activity can also contribute; the
per-session `STATISTICS IO` values provide the statement-level check.

The Azure Monitor output contains one-minute Average and Maximum values for CPU
percentage, Data IO percentage, and Log IO percentage. Maximum preserves a
short spike that Average can dilute across the minute.

The expected shape is a CPU spike with comparatively low Data IO and no Log IO.
Azure Monitor's **Data IO percentage** is a utilization percentage, not a
page-server-read count. The per-session SQL output is the attributable evidence
for page-server reads.

Azure Monitor publication is not immediate. If its output has no points for the
workload yet, keep the evidence directory and query the preserved UTC interval
again later rather than rerunning the workload blindly.

Azure Monitor can label the one-minute aggregate at the minute boundary after
the SQL workload. For example, a workload that ran from 02:33:27 through
02:33:49 UTC appeared in the 02:34 UTC metric bucket. In Metrics Explorer, use
**CPU percentage**, **1 minute**, and **Maximum**, and include at least one
minute after the preserved workload interval. Average or automatic granularity
can visually dilute a short spike.

The missing-index recommendation is evidence of the access-path gap, not
permission to create an index. The investigation has found the issue: this
query has no supporting access path for its `ValueNumeric` predicate, so it
scans roughly 108 million rows and drives the observed CPU spike. Observability
stops with that evidence-backed diagnosis. Performance returns to these
measurements to evaluate possible solutions and their performance, storage,
and write-cost tradeoffs; it does not assume that the raw missing-index
recommendation is automatically the right design.

## What repeatable means

The investigation and its evidence chain are repeatable:

- exactly three concurrent, read-only scans execute;
- each scan performs roughly 1.1 million logical reads against the seeded
  108-million-row observation table;
- `sys.dm_db_resource_stats` captures the short CPU interval at 15-second
  resolution;
- Azure Monitor publishes the corresponding one-minute CPU metric;
- `sys.dm_io_virtual_file_stats(0, NULL)` measures the RBPEX I/O delta across
  the workload;
- `sys.dm_io_virtual_file_stats()` measures the page-server I/O delta across
  the workload;
- Query Store attributes the executions, CPU, duration, and logical reads to
  the marked statement; and
- the stored Query Store plan identifies the missing index on the unindexed
  `ValueNumeric` predicate.

The exact measurements are not deterministic. CPU percentage, elapsed time,
parallel scheduling, publication delay, and the RBPEX/page-server split vary
between runs. Therefore, the scenario promises a visible, correlated CPU spike,
an attributable expensive query, and measured lower-tier reads—not a particular
CPU percentage, saturation, duration, or page-server-read count.

## Live validation

The complete single-command reader workflow was executed against an 8-vCore
Hyperscale `wardgeneral` database on 2026-08-30. All three sessions exited
successfully, the SQL drill-down completed, Azure Monitor returned metric
samples, and all six expected evidence files were written.

The workload ran from 02:33:27 through 02:33:49 UTC. The three sessions each
performed about 1.1 million logical reads, consumed 21.3–22.3 seconds of CPU,
and completed in 14.3–16.1 seconds. The compute cache was warm, so synchronous
and read-ahead page-server counters were all zero.

The database DMV captured consecutive 15-second CPU samples of 41.80% and
66.89%, with Data IO and Log IO at 0%. After publication, Azure Monitor reported
27.25% Average and 67% Maximum CPU in the 02:34 UTC bucket, confirming the same
spike at one-minute resolution. An earlier equivalent run reached 78%; that
variation is expected and is why the scenario does not promise an exact peak.

Query Store attributed three executions, 62.7 seconds of total CPU, 48.1
seconds of total duration, and 3,288,802 logical reads to the marked statement.
The missing-index signal identified `ValueNumeric` as the inequality column and
`ObservationType` as an included column, with an estimated impact of 84.32%.
That recommendation came from the execution plan stored in Query Store, not a
separate missing-index DMV lookup.

These are observed validation results, not promised values. Compute size,
concurrent activity, cache state, and scheduler timing change the measurements.

The buffer-pool-reset version of the workflow was validated on 2026-08-31.
After `DBCC DROPCLEANBUFFERS` removed clean pages, all three scans showed
page-server read-ahead while the virtual-file deltas showed both lower tiers:
RBPEX served about 1.86 GB and page servers served about 8.48 GB. The exact
counter deltas were 227,514 RBPEX reads and 173,783 page-server reads. These
read counts are not directly comparable as physical I/O operations because
RBPEX accounts local cache access in 8-KB pages and large page-server reads can
use scatter-gather I/O.

The same run reached 96.61% CPU and 38.74% Data IO in the 15-second database
samples. After publication, Azure Monitor reported 31.25% Average and 97%
Maximum CPU, plus 12% Average and 39% Maximum Data IO, in the 23:25 UTC bucket.
Log IO remained at 0%. Query Store attributed three executions, 71.8 seconds
of CPU, 56.4 seconds of duration, and 3,284,202 logical reads to the marked
statement. The stored plan retained the 84.32% `ValueNumeric` /
`ObservationType` missing-index recommendation.

## Sources

Microsoft Learn, accessed 2026-08-30:

- [Supported metrics for Microsoft.Sql/servers/databases](https://learn.microsoft.com/azure/azure-monitor/reference/supported-metrics/microsoft-sql-servers-databases-metrics)
- [`sys.dm_db_resource_stats`](https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-objects/sys-dm-db-resource-stats-azure-sql-database)
- [`sys.query_store_runtime_stats`](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-query-store-runtime-stats-transact-sql)
- [Hyperscale performance diagnostics](https://learn.microsoft.com/azure/azure-sql/database/hyperscale-performance-diagnostics)

## A note on the data

**All data is synthetic. There is no real patient data (PHI) here.** The dataset
is educational and must not be used for clinical, diagnostic, or other
real-world healthcare decisions.
