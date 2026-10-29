# Stage 3 — Tune Ward General

**Owning skill:** `tune-wardgeneral-data`

Prompt: **Run Performance Demo 3: demonstrate JSON indexing and memory grant
feedback on Ward General.**

Demo 3 contains two self-contained examples that do not depend on Demo 2 data
growth:

- `json-index/` creates a five-million-row archive of synthetic lab-result
  documents and compares the same selective array predicate before and after
  a JSON index.
- `memory-grant-feedback/` demonstrates row-mode memory grant feedback across
  eight executions of the same cached Sort over `clinical.ShiftReportArchive`,
  with Query Store attribution for every feedback feature that intervenes.

Observation tuning remains deferred. It will use measured plans, duration,
I/O, and storage rather than accepting an index recommendation blindly.

The `CREATE JSON INDEX` reference still labels the feature preview and lists
SQL Server 2025. The syntax has been live-validated on this project's Azure SQL
Hyperscale database, but its documented Azure SQL status must be rechecked
before documentation freeze.

## JSON-index sequence

The recommended path captures both actual plans automatically. SSMS is optional
for graphical inspection afterward:

```powershell
./json-index/run-demo.ps1
./json-index/run-demo.ps1 -Execute
```

The first command previews the target and explains that the JSON index build is
offline. `-Execute` is explicit approval to run that build. It creates the
fixture, captures the baseline actual plan, builds the JSON index, captures the
indexed actual plan, writes `plan-summary.csv`, and always runs cleanup.
Generated evidence is written under
`json-index/results/runs/<UTC timestamp>/`.

Expected console output resembles:

```text
Before index: Operator=Clustered Index Scan; JsonIndexAccess=False; IndexKind=Clustered; Index=[PK_LabResultArchive]; ActualRows=5000005
After index: Operator=Index Seek; JsonIndexAccess=True; IndexKind=Json; Index=[json_index_search_optimization_nci]; ActualRows=5
```

The run directory should contain:

| File | Evidence |
| --- | --- |
| `before-index.sqlplan` | Actual baseline plan with the clustered index scan. |
| `after-index.sqlplan` | Actual indexed plan with the internal JSON index seek. |
| `plan-summary.csv` | Extracted operator, JSON-index, index-kind, and row-count attributes. |
| `before-output.txt` | Baseline rows, I/O, timing, and actual-plan XML. |
| `index-build-output.txt` | Offline JSON-index build and catalog confirmation. |
| `after-output.txt` | Indexed rows, I/O, timing, and actual-plan XML. |

### Open the JSON plans in SSMS

1. In SSMS, select **File > Open > File** and open `before-index.sqlplan` from
  the latest timestamped results folder.
2. Find the **Clustered Index Scan** on `clinical.LabResultArchive`. Hover over
  it or press **F4** for Properties. Confirm the object is
  `PK_LabResultArchive` and Actual Rows Read is approximately 5,000,005.
3. Open `after-index.sqlplan` beside it. Find the **Index Seek** on the internal
  `sys.json_index_*` table. In Properties, confirm the index is
  `json_index_search_optimization_nci` and the object has
  `IndexKind="Json"`.
4. Compare the plans side by side. The baseline reads the entire archive; the
  indexed plan seeks the JSON posting index and returns the same five critical
  rows. Showplan calls the operator `Index Seek`; `IndexKind="Json"` proves it
  is the JSON-index access path.

The underlying scripts remain individually runnable:

1. `json-index/01-setup.sql` — create five critical lab-result documents and
  five million routine documents in 50,000-row batches.
2. `json-index/02-before.sql` — capture the baseline plan, reads, and duration.
3. `json-index/03-create-index.sql` — deliberately perform the offline index
  build with array-search optimization.
4. `json-index/04-after.sql` — repeat the identical predicate and compare
  evidence.
5. `json-index/05-cleanup.sql` — drop only the JSON index and archive table
  created by this example.

The predicate finds the five documents whose `$.flags` array contains
`critical`. Both queries use `MAXDOP 1` so parallelism does not hide the
scan-versus-index difference.

Live validation on `wardgeneral` at `HS_Gen5_40` returned the same five rows
before and after the index:

| Measurement | Before | After, warm |
| --- | ---: | ---: |
| Base-table logical reads | 162,050 | 20 |
| JSON-index logical reads | 0 | 4 |
| CPU time | 17,391 ms | below 1 ms reporting resolution |
| Elapsed time | 20,686 ms | below 1 ms reporting resolution |

The indexed query used 24 total data/index reads, **6,752 times fewer** than
the baseline. The first execution after index creation also spent 2,152 ms
compiling; the warm repeat had no measurable compile or execution time. Exact
times depend on service objective and cache state, so the repeatable evidence
is the identical result and the logical-read reduction.

Query Store preserved both plans. Baseline plan `516` contained no index seek.
Indexed plan `521` contained `PhysicalOp="Index Seek"` against the internal
`sys.json_index_759673754_1216000` table and its
`json_index_search_optimization_nci` index. Showplan uses the generic operator
name `Index Seek`; the object property `IndexKind="Json"` proves that the seek
uses the JSON index.

## Memory-grant-feedback sequence

This sequence is independent of stage 2 data growth. It creates a bounded,
demo-owned archive of five million nursing shift reports. The `UnitCode`,
`AcuityCode`, and `ShiftType` predicates are strongly correlated, while current
single-column statistics describe each column independently. The combined
estimate can undersize the memory grant for sorting the 50,000 matching wide
ICU reports. A covering `UnitCode` index seeks directly to those rows so the
Sort spill, rather than a shared five-million-row scan, controls the runtime.
The setup does not disable automatic statistics, use
`NORECOMPUTE`, change existing Ward General rows, or change database-scoped
configuration.

The recommended path is fully automated and does not require SSMS to capture
the plans or require manually enabling an execution plan. SSMS is optional for
graphical plan inspection afterward:

```powershell
./memory-grant-feedback/run-demo.ps1
./memory-grant-feedback/run-demo.ps1 -Execute
```

The first command previews the target. `-Execute` runs setup, executes the
query eight times, saves actual plans for executions 1 and 2, writes
`plan-summary.csv`, reports Query Store feedback, and always runs scoped
cleanup. Generated evidence is written under
`memory-grant-feedback/results/runs/<UTC timestamp>/`.

### Expected automated output

The setup should report compatibility level `170`, 5,000,000 total rows,
50,000 matching `ICU` / `Critical` / `Night` rows, and current statistics. The
runner's actual-plan summary should resemble:

```text
Execution 1: SortWarning=True; SpillLevel=1; Grant=271.89 MB; Used=271.89 MB; MGF=No: First Execution; ActualRows=50000
Execution 2: SortWarning=False; SpillLevel=none; Grant=993.34 MB; Used=392.55 MB; MGF=Yes: Adjusting; ActualRows=50000
```

The exact grants and timings vary with service objective and current load. The
required transition is:

- execution 1 has a Sort warning and `SpillToTempDb`;
- execution 2 has no Sort warning;
- `IsMemoryGrantFeedbackAdjusted` changes from `No: First Execution` to
  `Yes: Adjusting`; and
- both executions return 50,000 actual rows through the same plan shape.

The run directory should contain:

| File | Evidence |
| --- | --- |
| `execution-1.sqlplan` | Actual plan with the Sort spill warning. |
| `execution-2.sqlplan` | Actual plan after MGF adjusts the grant. |
| `plan-summary.csv` | Extracted warning, spill, grant, feedback, and row-count attributes. |
| `run-output.txt` | Eight-execution DMV results and Query Store feedback records. |

### Open the captured plans in SSMS

1. In SSMS, select **File > Open > File** and open
  `execution-1.sqlplan` from the latest timestamped results folder.
2. In the graphical plan, find the **Sort** operator with the yellow warning
  triangle. Hover over it or press **F4** to open Properties. Under
  **Warnings**, confirm the spill to tempdb and spill level 1. The XML form of
  the same warning is `SpillToTempDb`.
3. Select the root **SELECT** operator and inspect its memory-grant properties.
  Confirm `IsMemoryGrantFeedbackAdjusted` is `No: First Execution`.
4. Open `execution-2.sqlplan` beside it. Its Sort has no warning triangle and
  no `SpillToTempDb` warning. On the root SELECT, confirm
  `IsMemoryGrantFeedbackAdjusted` is `Yes: Adjusting` and
  `LastRequestedMemory` matches execution 1's requested grant.
5. Compare the two plans side by side. Both should retain the covering Index
  Seek and 50,000 actual rows; the changed memory grant and removed spill are
  the teaching point, not a changed access path.

The underlying scripts remain individually runnable:

1. `memory-grant-feedback/01-setup.sql` — verify compatibility level, Query
  Store, and MGF settings; create and populate `clinical.ShiftReportArchive`;
  build current `FULLSCAN` statistics on all three predicate columns; and
  create `clinical.DemonstrateMemoryGrantFeedback`.
2. `memory-grant-feedback/02-run.sql` — execute the same cached statement eight
  times. It automatically returns actual Showplan XML for executions 1 and 2,
  then reports plan generation, `GrantMB`, `UsedGrantMB`, `SpillPages`,
  `ElapsedTimeMs`, and Query Store feedback.
3. `memory-grant-feedback/03-cleanup.sql` — drop only the procedure and table
  created by this sequence. Run cleanup before repeating setup.

Live validation on `wardgeneral` at `HS_Gen5_40` showed memory grant feedback
correcting the grant on the second execution:

| Execution | Grant MB | Used grant MB | Spill pages | CPU ms | Elapsed ms |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 9.09 | 9.09 | 49,984 | 2,922 | 4,121.210 |
| 2 | 599.13 | 392.55 | 0 | 1,531 | 1,980.413 |
| 3–8 | 599.13 | 392.55 | 0 | 1,484–1,672 | 1,887.611–1,950.268 |

Query Store recorded `Memory Grant Feedback` in `FEEDBACK_VALID` state with
an additional 613,000 KB for the Sort. It recorded no CE feedback row during
the clean eight-execution run, and `PlanGenerationNumber` remained `1`.

Query Store plan `537` used an `Index Seek` on
`IX_ShiftReportArchive_UnitCode` and no table scan. The plan generation did not
change, so the measured difference is the grant correction rather than an
access-plan change.

The result proves that MGF corrected the underestimated grant, eliminated a
390.50 MB spill, reduced CPU by roughly half, and improved elapsed time by 52%
on execution 2. Warm executions remained 54% faster than execution 1.

The automated actual-plan capture was also live-validated. Its instrumentation
changed the compiled grant values, but retained the behavior and runtime
contrast:

| Execution | Sort warning | Spill level | Grant MB | MGF plan attribute | Elapsed ms |
| ---: | --- | ---: | ---: | --- | ---: |
| 1 | Yes | 1 | 271.89 | `No: First Execution` | 3,297.545 |
| 2 | No | — | 993.34 | `Yes: Adjusting` | 1,944.036 |

Both actual plans reported 50,000 rows. The runner saved them as
`execution-1.sqlplan` and `execution-2.sqlplan`; execution 1 contains
`SpillToTempDb`, while execution 2 has no Sort warning. Even with plan-capture
overhead, execution 2 was 41% faster.

Memory grant feedback is an Azure SQL Database IQP feature, not a
Hyperscale-exclusive feature. This example runs on the Ward General Hyperscale
database so the area tunes the same system throughout.

## Sources

- [microsoft/bobsql — SQL Server 2025 JSON demo](https://github.com/microsoft/bobsql/tree/master/demos/sqlserver2025/json), accessed 2026-09-12.
- [Microsoft Learn — `CREATE JSON INDEX`](https://learn.microsoft.com/sql/t-sql/statements/create-json-index-transact-sql), accessed 2026-09-12.
- [Microsoft Learn — Memory grant feedback](https://learn.microsoft.com/sql/relational-databases/performance/intelligent-query-processing-memory-grant-feedback), accessed 2026-09-12.
- [Microsoft Learn — `sys.query_store_plan_feedback`](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-query-store-plan-feedback), accessed 2026-09-13.
- [Microsoft Learn — `sys.dm_exec_query_stats`](https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-objects/sys-dm-exec-query-stats-transact-sql), accessed 2026-09-12.
