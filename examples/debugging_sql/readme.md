# Debugging SQL Server

Hands-on Windows SQL Server debugging labs using WinDbg, public symbols,
diagnostic queries, and controlled reproductions.

## Start here

Use an isolated Windows SQL Server instance, SSMS/sqlcmd, and WinDbg. Inspect
the command files for executable, symbol-cache, instance, and dump paths before
running them. Workloads may also require the SQL Server RML `ostress` tool.

| Lab | Focus |
| --- | --- |
| [1_getting_started](1_getting_started/readme.md) | Attach, inspect threads and symbols, and detach safely |
| [2_av](2_av/readme.md) | Access-violation reproduction and analysis |
| [3_hang](3_hang/readme.md) | Hang diagnosis and scheduler-deadlock reproduction |
| [4_query_abort](4_query_abort/readme.md) | Investigate query cancellation |
| [5_debug_latch_and_waits](5_debug_latch_and_waits/readme.md) | Trace latch and wait behavior |
| [6_spinlocks](6_spinlocks/readme.md) | Observe spinlock contention and high CPU |
| [7_unexplainedcpu](7_unexplainedcpu/readme.md) | Correlate CPU with access checks and query profiling |

Follow the selected lab's sequence rather than executing every script. Attaching
a debugger can pause the entire process; some reproductions deliberately crash
or hang it. Never run these labs against production. End workloads, remove lab
objects using the selected lab's cleanup steps, and detach the debugger without
terminating SQL Server when a crash is not intended.

Use the `debugging-sql` workspace skill for guided lab selection.
