---
name: waits-latches-spinlocks-workshop
description: "Guide the numbered Inside Waits, Latches, and Spinlocks workshop: WinDbg basics, blocking, scheduler yield, preemptive waits, threadpool exhaustion, log governance, latches, and spinlocks. Use for examples/insidewaitslatchesspinlocks_workshop."
---

# Waits, latches, and spinlocks workshop

## Procedure

1. Read the [module map](../../../examples/insidewaitslatchesspinlocks_workshop/readme.md).
   Select a numbered module and read its own README and scripts. This is
   separate from the shorter `insidewaitslatchesspinlocks` collection.
2. Verify the isolated Windows SQL Server build, WinDbg/symbol setup, SQL
   tools, and required stress driver. Start with module 0 when debugger
   prerequisites or safe attach/detach procedures are unfamiliar.
3. Review targets, authentication, startup flags, affinity, Resource Governor,
   worker limits, and cleanup. Obtain explicit approval before process
   attachment, instance changes, server restarts, or heavy/failure workloads.
4. Capture baseline request/wait, CPU, latch/spinlock, or log observations.
   Use separate workload/diagnostic sessions and prepare DAC access before
   threadpool experiments that may block ordinary connections.
5. Run only the approved module sequence. Resolve internal symbols and type
   IDs against the actual build; distinguish waits and cumulative counts from
   evidence of the reproduced bottleneck. Captured driver files are historical.
6. Stop only the specific lab process IDs, close transactions, detach safely,
   restore configuration, and follow module cleanup before continuing.

Never run these reproductions in production. Keep dumps/logs private until
reviewed and follow [secret checks](../../../SECRET-SCANNING.md).
