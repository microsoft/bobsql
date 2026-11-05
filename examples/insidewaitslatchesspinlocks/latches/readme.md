# Latch investigations

Choose one isolated SQL Server lab:

- [buflatch](buflatch/readme.md): buffer/page inspection and latch observations.
- [debug_latches](debug_latches/readme.md): a controlled latch reproduction with
  diagnostics and debugger attachment.

Read the selected area's original text instructions, check local paths, and
prepare the required SSMS/sqlcmd, WinDbg, and workload tools. Latches are
internal synchronization primitives; their evidence and symbol names depend
on the server build. Never attach these reproductions to production.

Stop workload drivers, detach the debugger, and follow the selected cleanup
before moving to another scenario.
