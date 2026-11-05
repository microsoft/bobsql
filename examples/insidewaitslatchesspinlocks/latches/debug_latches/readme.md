# Debugging a latch reproduction

Follow [readme.txt](readme.txt) for setup, reproduction, and observations.
Review [repro.cmd](repro.cmd), [insert.sql](insert.sql), and
[debugsql.cmd](debugsql.cmd) before starting.

The lab requires an isolated Windows SQL Server instance, the SQL/workload
tools named in the scripts, and WinDbg with symbols. Keep a separate session
for [dmvs.sql](dmvs.sql) and [find_a_latch_class.sql](find_a_latch_class.sql).
Attaching or breaking into the debugger pauses the process.

Stop the reproduction, detach without killing SQL Server when appropriate,
and inspect [cleanup.sql](cleanup.sql) before removing lab objects.
