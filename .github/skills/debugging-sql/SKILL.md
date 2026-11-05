---
name: debugging-sql
description: "Guide SQL Server debugging labs with WinDbg: access violations, hangs, scheduler deadlocks, query aborts, latches, spinlocks, and unexplained CPU. Use when working with examples/debugging_sql or choosing one of its seven labs."
---

# SQL Server debugging labs

## Procedure

1. Read the [collection map](../../../examples/debugging_sql/readme.md).
   Select the matching failure/observation lab; do not run all reproductions.
2. Read that lab's README and inspect command/SQL/native entry points. Confirm
   Windows SQL Server build, instance, privileges, WinDbg, symbol availability,
   SQL client tools, and any required stress driver.
3. Identify actions that attach, pause, crash, restart, or deliberately hang
   SQL Server. Require a disposable lab and explicit approval before them.
   Check local executable, dump, symbol-cache, database, and file paths.
4. Capture baseline requests/waits/stacks. Run only the approved reproduction,
   keeping a separate diagnostic or DAC connection where the lab requires it.
5. Correlate actual DMV, CPU, stack, exception, or dump evidence with the
   walkthrough. Symbol addresses and internal types are build-specific;
   distinguish unavailable symbols from proof of a different root cause.
6. Stop stress processes by their specific IDs, close lab transactions,
   follow the lab's cleanup, and detach without killing SQL Server unless the
   approved reproduction requires termination.

## Boundaries

Never attach these destructive reproductions to production. Preserve dumps
privately; dumps/logs can contain sensitive data. Use
[secret checks](../../../SECRET-SCANNING.md) before sharing source or captures.
