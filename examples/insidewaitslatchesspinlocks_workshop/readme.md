# Inside waits, latches, and spinlocks workshop

A numbered SQL Server workshop covering debugging, blocking, scheduling,
advanced waits, log governance, latches, and spinlocks. This is separate from
the [shorter waits/latches/spinlocks collection](../insidewaitslatchesspinlocks/readme.md).

| Module | Topic |
| --- | --- |
| [0_learnhowtodebug](0_learnhowtodebug/readme.md) | WinDbg attachment, symbols, and thread inspection |
| [1_debugwaits](1_debugwaits/readme.md) | Blocking waits and diagnostic evidence |
| [2_scheduleryield](2_scheduleryield/readme.md) | CPU scheduling, affinity, and workload observations |
| [3_advancedwaits](3_advancedwaits/readme.md) | Preemptive waits and worker exhaustion |
| [4_loggovernance](4_loggovernance/readme.md) | Log-rate governance |
| [5_latchbasics](5_latchbasics/readme.md) | Latch fundamentals |
| [6_buflatch](6_buflatch/readme.md) | Buffer/page latch investigation |
| [7_debug_latches](7_debug_latches/readme.md) | Debug a controlled latch reproduction |
| [8_spinlocks](8_spinlocks/readme.md) | Spinlock contention and backoff |

## Prerequisites and safety

Start with module 0 and the chosen module's own requirements. The workshop
uses an isolated Windows SQL Server lab, WinDbg with public symbols,
SSMS/sqlcmd, and workload tools referenced by the command files. Historical
instructions target older SQL builds; inspect paths, startup parameters,
authentication, and build-specific symbols before running.

Debugger attachment can freeze the process. Stress and failure reproductions
can exhaust workers or CPU, and configuration scripts can affect the whole
instance. Obtain approval before these operations; never run them in production.
Stop drivers, close transactions, restore changed settings, and follow each
module's cleanup before continuing.

Use the `waits-latches-spinlocks-workshop` workspace skill for guided selection.
Captured driver output is historical reference material, not current evidence.
