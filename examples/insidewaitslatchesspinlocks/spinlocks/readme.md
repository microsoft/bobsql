# Spinlock contention

The original [readme.txt](readme.txt) walks through LOCK_HASH contention,
WinDbg backoff breakpoints, and disassembly observations.

Use an isolated Windows SQL Server instance, public symbols, SSMS/sqlcmd, and
the workload driver referenced by [connectme.cmd](connectme.cmd) and
[resetit.cmd](resetit.cmd). Inspect authentication and server-start parameters
before running. The reproduction can create high CPU and connection pressure.

Capture [get_spinlock_stats.sql](get_spinlock_stats.sql) and
[execrequests.sql](execrequests.sql) before and during the workload. Symbol
addresses and spinlock type IDs are build-dependent; do not assume values in
old captures apply to the current build.

[ostress_connectme](ostress_connectme/readme.md) and
[Output_sp_reset_stress](Output_sp_reset_stress/readme.md) contain previous
driver output. Stop the drivers, detach the debugger, and restore lab startup
settings after the demonstration.
