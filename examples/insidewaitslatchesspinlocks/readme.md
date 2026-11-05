# Inside waits, latches, and spinlocks

SQL Server synchronization and scheduling labs, with DMV queries, WinDbg
walkthroughs, stress workloads, and Azure SQL log-governance examples.

| Area | Purpose |
| --- | --- |
| [debugwaits](debugwaits/readme.md) | Blocking waits, thread states, and scheduler yield |
| [latches](latches/readme.md) | Buffer latches and latch-debugging reproductions |
| [spinlocks](spinlocks/readme.md) | LOCK_HASH contention, CPU, and backoff observations |
| [loggovernance](loggovernance/readme.md) | Workloads and diagnostics for transaction-log rate governance |

Use a disposable lab, SSMS/sqlcmd, and the tools named by the selected area.
WinDbg labs require Windows SQL Server and symbols; load drivers may require
`ostress`. Review all instance names, paths, authentication, and resource limits.
Some scripts restart the server or intentionally generate severe contention.

Choose one scenario, capture baseline DMVs, run its workload in separate
sessions, and compare the resulting waits with the baseline. Stop stress
drivers and follow the area's cleanup before changing scenarios.

The original text walkthroughs are retained next to their Markdown entry
points. Use the `waits-latches-spinlocks` workspace skill for this collection.
