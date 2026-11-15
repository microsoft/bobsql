# SQL Server 2025 tempdb growth lab with SQLSimTools

## What this demonstrates

An evidence-first investigation: establish scope, classify occupied space,
identify its owner, test one explanation, and verify recovery. Follow the
[diagnostic guide](../readme.md), rather than treating large files as the cause.
This is a repository teaching example, not a quotation or prescribed personal
procedure from Bob Ward.

The workload creates 4,096 rows of synthetic data in a local temporary table,
reserving approximately 32 MB, holds the table for 90 seconds, then drops it.
It demonstrates **user-object space consumption and reuse**, not spills, version
retention, log exhaustion, or a deliberately slow query. `WAITFOR` is an
observation window, not evidence that tempdb caused a slowdown.

Physical file growth is intentionally **not forced**. Existing free extents can
satisfy the allocation. If files do grow, they need not shrink after cleanup.

## Prerequisites and safety

- An approved **non-production SQL Server 2025** instance; the commands below
  target `localhost` using Windows authentication.
- [SQLSimTools](https://aka.ms/sqlsimtools), installed here at
  `C:\sqlsimtools_release`; adjust the executable path for another installation.
- At least **48 MB of reusable tempdb data space**, plus disk/log headroom.
  The workload checks reusable data space and stops if insufficient. Check
  capacity before running; concurrent workloads can still consume that space.
- Monitoring permissions described in the [guide](../readme.md), including
  `VIEW SERVER PERFORMANCE STATE` for the cross-session check.

Run **one thread and one iteration**. No user database, persistent object,
open user transaction, instance setting change, shrink, or restart is required.
Other sessions can affect global counters, so the assertions use the lab's own
allocation rather than assuming exclusive access to tempdb.

## 1. Prepare SSMS and take a baseline

In SSMS 22.7+ with the AI Assistance workload and Copilot access, use Agent mode.
Confirm `tempdb-growth` appears under Copilot Chat **Tools > Skills**.
Workspace skills live under the repository's `.github\skills` directory.
See [SSMS skill discovery and prerequisites](https://learn.microsoft.com/ssms/github-copilot/agent-skills).

Keep the skill and its linked `troubleshoot` files together. Copying only
`SKILL.md` into a personal skill directory breaks those relative links; use
the repository workspace or adapt the links and copy the supporting kit.

Open an SSMS query window connected to `localhost`, database `tempdb`.
Run [01-space.sql](../01-space.sql) and retain the baseline privately.

## 2. Start the reproduction

From `C:\bobsql` in PowerShell:

```powershell
$sqlsim = 'C:\sqlsimtools_release\sqlsim\x64\sqlsim.exe'
& $sqlsim -S localhost -E -d tempdb -app BobWard-TempdbGrowth-Lab `
    -n 1 -r 1 -l 5 -t 180 -stoponerror `
    -i '.\troubleshoot\tempdb\growth-and-slow-workloads\demo\reproduce.sql'
if ($LASTEXITCODE -ne 0) { throw 'Tempdb lab failed; inspect SQLSimTools errors.' }
```

Wait for allocation to complete, then use the 90-second observation window.
The SQL script reports the session ID and an allocation PASS. Some clients
buffer output; run the observer check below to confirm readiness.
Do not use the CLI's default query timeout: it can expire during the hold.

## 3. Investigate with the SSMS skill

Use this prompt:

> Use tempdb-growth. On my approved local SQL Server 2025 instance, investigate
> the current tempdb space consumption using the read-only diagnostic kit.
> Compare with my baseline, classify the allocation, identify its session,
> and distinguish observed facts from hypotheses. Keep SQL text disabled.
> Do not kill sessions, shrink files, or change configuration.

Run [01-space.sql](../01-space.sql), then [02-consumers.sql](../02-consumers.sql)
in the observer window, not the workload connection.
Run [verify-active.sql](verify-active.sql) during the hold as a deterministic
cross-session test. It fails explicitly if the lab is absent, duplicated, or
below its 32 MB allocation threshold. It is a **lab assertion**, not a
production diagnostic.

Expected evidence:

| Observation | Interpretation |
| --- | --- |
| User-object allocation increases by roughly 32 MB | The temporary table explains this lab's allocation |
| Lab session has at least 32 MB net user-object allocation | Ownership is established; match its ID to the workload output |
| Lab request normally waits on `WAITFOR`, without a blocker | Intentional hold, not a storage wait or blocking incident |
| File sizes may remain unchanged | Allocating existing extents does not require autogrowth |
| Internal objects or version-store totals may differ independently | Do not attribute unrelated concurrent activity to this workload |

During the hold, this command can also run the observer test with SQLSimTools
from a **second** PowerShell window:

```powershell
$sqlsim = 'C:\sqlsimtools_release\sqlsim\x64\sqlsim.exe'
& $sqlsim -S localhost -E -d tempdb -l 5 -t 30 -stoponerror `
    -i '.\troubleshoot\tempdb\growth-and-slow-workloads\demo\verify-active.sql'
if ($LASTEXITCODE -ne 0) { throw 'Active-owner verification failed.' }
```

## 4. Resolve, verify, and clean up

The workload drops its table after 90 seconds. It allows up to 30 additional
seconds for deallocation, then asserts that its session's net user allocation
is within **2 MB of baseline**. It reports a cleanup PASS and before/after
data-file sizes. A failed assertion raises a SQL error and a nonzero CLI exit.

Rerun the diagnostic scripts and compare occupied space and reusable extents.
File size is not the success criterion. The correct lab resolution is to
release the no-longer-needed temporary object, not shrink tempdb.

After SQLSimTools exits, this read-only SSMS check should return no rows:

```sql
SELECT session_id, program_name, status
FROM sys.dm_exec_sessions
WHERE program_name = N'BobWard-TempdbGrowth-Lab';
```

No separate database cleanup is needed: all lab tables are session-local and
disappear on disconnect, including after a failure. If stopping early, cancel
only this SQLSimTools invocation and verify its connection closes. If space
is still retained, collect evidence for deferred deallocation/version cleanup;
do not kill unrelated sessions or restart the instance.

For a negative test, run `verify-active.sql` with no lab running: it must fail,
not report success. No production query text or captures belong in this repo.
