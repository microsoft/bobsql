# Local SQL versioning demo apps

Five light navy-and-silver presentation pages share a local Flask backend.
Presentation sizing is always on; there is no alternate mode or sizing toggle.
The Cowboys silver background and compact headings keep demo cards and the
first execution controls visible without scrolling on typical laptop screens.
Demo 1-4 show one step at a time with its exact SQL batch always visible.
Prerequisites and earlier results expand on demand;
destructive steps still require confirmation.
SQL uses locally served SSMS-style syntax colours: blue keywords/types,
red strings, green comments, and purple variables/functions/numbers. The same
renderer covers setup, walkthrough steps, executed SQL history, and benchmark
workload SQL. Highlighting preserves the exact source text and does not change
what executes. No CDN or additional package is needed.
Template changes appear on browser refresh without restarting SQL
sessions or enabling Flask's process reloader.
SQL runs on your local SQL Server 2025 instance using your Windows account
and integrated authentication. No credentials, CDN, or cloud services are needed.

## Start

From this directory:

```powershell
.\start.ps1
```

The launcher reuses a healthy backend or starts one hidden in the background,
verifies readiness, and opens a **new normal Edge/Chrome browser window**.
No extra console window is needed. It reports the backend PID and saves stdout
and stderr logs under `%LOCALAPPDATA%\bobsql\sqlversioning`, named by port.
It does not execute setup or demo SQL. Use `-NoBrowser` only for
health checks. A repository skill records this as the "run the app" workflow.

For manual startup, or if dependencies are missing:

```powershell
python -m pip install -r requirements.txt
python app.py --server localhost --port 5080
```

Open <http://127.0.0.1:5080>. Each demo has its own page:

| Demo | Name | Source folder | Browser URL |
|------|------|---------------|-------------|
| 0 | Setup | [demo0-setup](../demo0-setup/) | `/demo/0` |
| 1 | Blocking | [demo1-blocking](../demo1-blocking/) | `/demo/1` |
| 2 | RCSI & Snapshot | [demo2-rcsi-snapshot](../demo2-rcsi-snapshot/) | `/demo/2` |
| 3 | Version Store Internals | [demo3-version-store](../demo3-version-store/) | `/demo/3` |
| 4 | ADR & PVS | [demo4-adr-pvs](../demo4-adr-pvs/) | `/demo/4` |

Numbers remain in the folder names, navigation, headings, script filenames,
and browser URLs. Existing browser links and saved step history continue to work.

For a named local instance use `--server '.\SQL2025'`.
The server binds only to loopback and rejects cross-origin execution requests.
Run it from your normal Windows session with appropriate SQL permissions;
these diagnostic demos assume SQL Server sysadmin.

## Present

1. Demo 0 has one **Run setup** button. Setup is **destructive**: it drops and
   recreates `starswillwinthecup`, `eaglesdontfly`, and `howboutthemcowboys`
   and seeds their data. Review the expandable SQL and confirm the prompt.
   After successful setup, three visual database cards show their tables and
   approximate row totals. Raw result tables are expandable. Saved setup
   inventory survives a backend restart when browser history storage is available,
   and is labeled as a previous setup rather than current database state.
   No separate readiness step is needed.
   The database cards use locally served Dallas Stars, Philadelphia Eagles,
   and Dallas Cowboys logos, not generic symbols.
2. Select a demo and sub-demo. Opening or refreshing a demo starts at its first
   subdemo (2a, 3a, or 4a), not a previously remembered selection. Selecting a
   subdemo never runs SQL or resets active sessions.
   Only one step is visible, with its session,
   explanation, **Run** button, and exact SQL batch, as in an SSMS query window.
   Page-inspection steps instead have **Open page viewer**, not raw DBCC PAGE
   SQL or results. The existing formatted Demo 3 and ADR viewers open in a new
   tab on the same backend, with database, table and row prefilled. Click
   **View Page** there to inspect or refresh the evidence, then return and
   use **Next**. Opening the tab alone does not run SQL; viewer diagnostics
   use separate autocommit connections and leave demo sessions untouched.
   No separate viewer process or port is required.
   A short explanation stays visible; full instructions and safety details
   remain under **Prerequisites & safety**. Long SQL/results scroll inside their
   own panels rather than sending you down a list of steps.
   **Previous**, **Next**, and the step picker only change the displayed step;
   they never execute SQL or wait for a running query. The selected step's
   actual result appears in its session pane on the right. Admin-query results
   stay in a collapsed **Admin result** expander below the SQL on the left.
   Admin steps have a wider SQL column; expand results when needed instead of
   reserving code space for old output. Expanded Admin results, tables, and
   messages grow down the page without vertical height limits; scroll the web
   page to read long results. Opening results does not shrink the SQL pane.
   Admin table headers and values stay on one line; wide tables scroll
   horizontally instead of wrapping column names. Configuration guidance reports whether
   app sessions are open: **End demo** is needed only if they are still open.
   Saved results are labeled as previous
   evidence, not current database state.
   The current step has a navy highlight. Completed steps turn grey, receive
   a check mark in the step picker, and their **Run** button becomes disabled
   **Completed**. **Next** stays highlighted. Successful results and expected
   SQL errors count as completion; failures and cancellations do not.
   To repeat deliberately, expand **Instructions & Run again** and confirm
   **Run again (intentional repeat)**. SQL and earlier results remain readable.
   After finishing a demo, its first configuration step is available to start
   a fresh walkthrough; old executions do not mark later steps complete in
   the new run. Saved results from a previous backend are not completion.
   Demo 1 separates preparation, **Reader waits**, **NOLOCK reads dirty data**,
   and cleanup. Writer/Reader labels make the session handoffs explicit.
   The right side compares **Session 1** and **Session 2** side by side, with
   no Admin column. Each pane retains its executed statement and actual result
   while you work in the other session. Selecting an executed step shows that
   step's result in its session; the other pane keeps its latest executed step.
   Live connection/transaction state is labeled separately from result evidence.
   Balances are the last single-row values returned up to the displayed execution,
   not simulated or continuously sampled balances. A blocked pane is highlighted
   only when the live DMV sample identifies it as blocked. SQL/messages remain
   expandable and result tables scroll inside each pane.
3. Sessions 1 and 2 are independent, persistent SQL connections. Explicit
   transactions remain open across clicks. A blocked reader does not freeze
   the browser: advance the writer's commit step to release it.
4. Both sessions' state, results, and blocking remain visible. Background DMV
   monitoring powers those live indicators; detailed measurements appear only
   in the numbered Admin steps. Earlier results/balance comparisons are in a
   full-width expander below the walkthrough. Actual query results, error 3960, and formatted page evidence
   are separate from explanatory text. Result tables display at most
   1,000 rows. Version cleanup timing and internal page formats vary by build.
5. **End demo sessions** before switching demos or running database
   configuration steps. This cancels running work, rolls back unfinished
   transactions, and closes only this app's SQL connections.
   After the last cleanup SQL succeeds, the walkthrough's **Next** control
   becomes **Finish demo — close sessions**. Click it and confirm to complete
   the handoff. A success message confirms that connections are closed and
   you can run the next demo's configuration. Cleanup SQL alone does not
   close the app connections. The header's **End demo** remains available
   for early exit or cancellation.

### Resetting a walkthrough

Each Demo 1-4 page has **Reset demo** for its selected subdemo (for example
**Reset demo 2b**). Confirm it to undo that walkthrough's known SQL changes,
close its connections, clear completed-step progress, and return to step 1.
Earlier execution history is retained. Run the steps manually to present again.
**End demo** remains connection cleanup only; it does not undo committed changes.
Demo 0 still uses its separate, destructive **Run setup** action.

Reset uses explicit demo-specific SQL, not new backups, snapshots, or database
recreation. It restores the demo's defined starting balances and default text,
reverses recorded committed increment waves (including intentional repeats and
partial presentations), removes the FK fix index for 2e, and restores the
selected subdemo's starting ADR/RCSI/SNAPSHOT/optimized-locking settings.
This is a reset to the demo's defined starting state, not restoration of
arbitrary values from before a presentation. Physical page layout, version-store
sizes, cleaner timing, timestamps, and arbitrary SSMS changes are not rewound.

The FK/ghost/recovery demos reuse their existing session-local restoration
tables before closing those sessions. Wait for a busy restoration session to
finish before resetting; do not close it first. If required tables were lost,
execution history is unavailable after a backend restart, another walkthrough
ran afterward, or a failed/cancelled committed write is ambiguous, reset stops
with an error instead of guessing. Use the original restoration steps or
explicitly approved Demo 0 when needed. Other SQL connections using the affected
databases must be closed; Reset demo does not kill other users' sessions.
Both reset connection checks exclude connections tagged as owned by this app,
including concurrent monitoring and embedded page viewers. Viewer diagnostics
use the runner's ownership-tagged autocommit connections and switch back to
master before closing, so pooled viewer connections do not keep a lab database
in use. A genuinely outside connection is reported
with its SPID, client name, and current database so it can be disconnected
without guessing which session caused the refusal.
The app's in-memory execution ledger is required for counter-based reversals;
browser-saved history is evidence only and is never trusted to modify SQL data.
If data restoration succeeds but restoring settings fails, retry Reset demo:
the app remembers the completed data reversal and does not apply it twice.
No new step can run until that incomplete reset is finished.

End demo does **not** undo committed updates, restore isolation/ADR options,
or recreate tables. Use each scenario's explicit restoration steps. Some
scenarios temporarily save rows in connection-local temporary tables:
complete their restoration before ending the sessions. If interrupted, use
approved demo 0 setup to restore the complete lab baseline.

Cancellation uses SQL `KILL` only after verifying the SPID belongs to this
running app instance. It closes the selected connection and rolls back its
transaction, rather than leaving a potentially unusable transaction open.

There is **no inactivity/session expiry** and demo queries have no execution
timeout. Open sessions stay alive until you explicitly end/cancel them or stop
the server; switching tabs or pausing the presentation does not roll them back.
Login attempts and read-only monitoring have short timeouts so connection
failures stay visible without freezing the UI. The Python server must remain
running and Windows must not sleep; OS sleep, SQL service restarts, or manually
killing the process cannot be prevented by the app.

Never close the browser assuming SQL transactions have ended. Use End demo
first, then stop the background server with `Stop-Process -Id <backend PID>`
using the PID reported by the launcher (or Ctrl+C for manual console startup).
Shutdown cleanup is best effort;
if the process is forcibly terminated, SQL Server rolls back disconnected sessions.

## Benchmark replay

Open **Benchmark replay** from the navigation, or visit `/benchmark`.
The single **Captured run** dropdown includes local comparisons:
**Inventory — Baseline** and **Inventory — ADR + RCSI**. Inventory uses the
200K-product capture and compares baseline with ADR + RCSI.
Write-stress captures have been removed; its setup/workload code remains
available for future testing. Inventory OL results are not presented pending
further testing.
It also offers **TPC-C — baseline vs ADR (published)** and
**TPC-E — baseline vs ADR (published)** using the published figures summarized
in `../benchmark/ctr-paper-results.html`: 13.8% and 2.4% throughput reduction.
These replay normalized relative throughput (100% baseline versus 86.2% or
97.6% with ADR), not fabricated execution counts. Baseline means traditional
tempdb versioning. The source is linked at <https://aka.ms/sqladr>.
These are not local sqlsim runs or separately measured ADR + RCSI results.
The published benchmark transaction mixes are displayed separately:
TPC-C is 8% read-only / 92% read/write; TPC-E is 76.9% read-only / 23.1% read/write,
from Table 1 of [TPC-E vs. TPC-C](https://cs-people.bu.edu/mathan/publications/sigrec10-chen.pdf).
These describe transaction roles, not physical IO or measured mix samples from
the ADR runs. No workload SQL or latency figures are invented.
Click the single **Run** button to start the selected replay. Repeat a replay;
completed comparisons remain visible without duplicate rows.
Each run animates execution counters and progress for 10 seconds, ending at the
exact captured total and adding the configuration to the comparison table.
An illustrative worker-to-SQL flow and color-coded throughput bars make the
playback visual. Completed bars retain their recorded rates for comparison.
The throughput display uses the original recorded runtime, not the compressed
playback duration. **Restart replay** cancels playback and clears the comparison.
The page shows actual saved execution totals, average latency, available
deadlocks, and query breakdowns. Executions/s and baseline ratios are calculated
using each configuration's recorded runtime. Missing metrics say **Not captured**.
Each workload row has **Expand SQL** for its current repository script.
Historical captures do not include original SQL text, so the code is explicitly
labeled as current source. The **% read / % write (workers)** column shows each
query's share of configured worker threads, with an overall mix below the table
(inventory: 62.5% read / 37.5% write).
These are workload-role percentages, not measured IO or execution shares;
write queries can also read rows internally.
Only the selected 200K-product inventory capture is offered.
The 50K inventory capture remains archived but is not shown.
Presentation labels omit timestamps; original capture metadata remains in the
JSON files and API for traceability. The page is labeled
**Replay — animated from recorded totals**. Intermediate counters are explicitly
interpolated, not measured time-series evidence or new measurements.

## Validation commands

Team logo assets are sourced from ESPN's
[Stars](https://a.espncdn.com/i/teamlogos/nhl/500/dal.png),
[Eagles](https://a.espncdn.com/i/teamlogos/nfl/500/phi.png), and
[Cowboys](https://a.espncdn.com/i/teamlogos/nfl/500/dal.png) images.
Logos remain the property of their respective owners and identify the
demo database themes; no affiliation or endorsement is implied.
The app serves them locally and needs no external image requests at runtime.

```powershell
python -m unittest discover -v
node --test test_sql_syntax.cjs
```

The unit tests do not alter SQL Server. Live rehearsals do change the three lab
databases and require an approved setup. The original scripts remain available
in the parent demo folders for comparison and SSMS fallback.

After approving setup, optionally rehearse all scenarios (or one):

```powershell
python test_live.py --run
python test_live.py --run --scenario 2b
```

This changes lab data/options and validates SQL execution, expected conflicts,
and session handoffs. It does not recreate databases. Run it with no concurrent
SSMS or browser demos against these databases. Cleaner progress still needs a
timed rehearsal: a successful DMV query does not prove that cleanup has finished.
