---
name: waits-latches-spinlocks
description: "Investigate SQL Server waits, scheduler yield, buffer latches, LOCK_HASH spinlocks, and Azure SQL log governance. Use when working with examples/insidewaitslatchesspinlocks and its debugwaits, latches, spinlocks, or loggovernance areas."
---

# Waits, latches, and spinlocks

## Procedure

1. Use the [collection map](../../../examples/insidewaitslatchesspinlocks/readme.md)
   to choose the scenario. Read its Markdown entry point and retained
   `readme.txt` instructions.
2. Confirm platform, SQL build/tier, instance, SQL tools, and the scenario's
   WinDbg/symbol or stress-driver dependencies. Review startup flags,
   authentication, local paths, and resource limits.
3. Use a disposable lab. Obtain approval before restarts, debugger attachment,
   Resource Governor changes, heavy traffic, bulk inserts, or configuration
   changes. Supply credentials privately; do not reuse literal demo passwords.
4. Capture baseline requests, wait/latch/spinlock counters, and CPU/log metrics.
   Run the approved workload in the intended sessions, then compare deltas and
   stacks rather than equating a cumulative wait count with the root cause.
5. Resolve spinlock type IDs and internal symbols against the current build.
   Captured driver output is reference material, not proof of current behavior.
6. Stop the specific lab processes, close transactions, detach the debugger,
   and follow the chosen cleanup while restoring prior settings.

Do not run contention or failure reproductions in production. Follow
[secret checks](../../../SECRET-SCANNING.md) before publishing logs or scripts.
