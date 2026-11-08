---
name: sql-versioning-apps
description: "Launch, run, review, rehearse, test, or update the local SQL versioning click-through apps in examples/sqlversioning/apps. Use when the user says run the app, start the app, open the app, demo apps, browser demos, SQL versioning visuals, or asks about the Cowboys-themed demo pages. In this repository, running the app means opening a NEW normal external browser window, not the VS Code integrated browser."
---

# SQL versioning click-through apps

## Run or open the app

1. Read [the app guide](../../../examples/sqlversioning/apps/README.md).
   The backend is local Flask, normally at `http://127.0.0.1:5080`, using
   Windows integrated authentication against local SQL Server 2025.
2. Run [the launcher](../../../examples/sqlversioning/apps/start.ps1):

   ```powershell
   & C:\bobsql\examples\sqlversioning\apps\start.ps1
   ```

   Resolve the repository root if the checkout is elsewhere. The launcher
   verifies/reuses an existing app, starts it only if needed, waits for
   readiness, checks SQL monitoring, and opens Edge/Chrome with `--new-window`.
   **Use a new normal external browser window, never the integrated VS Code
   browser, when the user says "run the app."** Browser automation for testing
   is separate and does not fulfill the launch request.
3. Keep newly started backend processes independent of the agent session:
   when launching through the shell tool, use its detached background mode
   and verify readiness. Do not restart a healthy server, kill unrelated
   processes, or create duplicates. An occupied unresponsive port is an error
   to investigate, not permission to replace its process.
4. Report the working URL and any SQL connection errors. Do not install
   packages unless the chosen command reports missing dependencies; then
   install from the app's existing requirements file.
5. There is no demo-query timeout or inactivity/session expiry. Do not add
   idle rollback, session expiry, automatic reconnection of an open
   transaction, or an auto-shutdown timer. Windows sleep or SQL/service
   termination can still interrupt the demo; keep the computer awake.

## Present or review

- Five pages `/demo/0` through `/demo/4` share one backend. Select a subdemo
  and run its numbered steps manually; never autorun SQL when opening a page.
- Names retain the numbers: 0 Setup (`demo0-setup`), 1 Blocking
  (`demo1-blocking`), 2 RCSI & Snapshot (`demo2-rcsi-snapshot`), 3 Version Store
  Internals (`demo3-version-store`), and 4 ADR & PVS (`demo4-adr-pvs`).
  Keep folder names, catalog source paths, and visible labels consistent;
  existing numeric browser URLs and step IDs stay stable.
- Preserve the light Cowboys silver background (`#b0b7bc`), navy accents,
  compact intro, and always-on presentation sizing without a mode toggle.
  Keep the first step card and
  Run button above the fold, including at 125% browser zoom. Long instructions
  and SQL expand on demand; destructive confirmations remain mandatory.
  No external logos/assets or CDN dependencies are needed.
- Sessions 1 and 2 are separate persistent connections. Blocked reads run
  asynchronously; advance the writer's commit/rollback to release them.
- Show actual balances, DMV blocking edges, version-store/PVS measurements,
  and DBCC evidence. Label explanatory illustrations; never invent
  measurements or promise deterministic cleanup timing.
- Configuration steps require **End demo** first. End demo cancels app-owned
  work, rolls back unfinished transactions, and closes app connections; it
  does not undo committed data or restore database options.
- Complete temporary-table-backed restoration steps before closing their
  sessions. Never run setup or live rehearsals implicitly as part of launch.

## Setup, validation, and cleanup

1. Load the `sql-versioning` skill for source-script context. Review setup
   before requesting approval: demo 0 drops/recreates three lab databases.
   Opening/running the web server alone must not modify SQL data.
2. Run `python -m unittest discover -v` from the apps directory for changes
   to the runner/catalog. Validate UI changes in a browser.
3. Only with approval, run `python test_live.py --run`, or add
   `--scenario 2b` for a targeted rehearsal. It modifies existing lab data and
   options; do not run alongside SSMS/browser demos on those databases.
4. Diagnostic connections remain autocommit and never read demo tables in
   open transactions. Capture expected conflict numbers with SQL
   `ERROR_NUMBER()`, not guesses from localized driver messages.
5. Leave the app running after a launch or review unless asked to stop.
   Before a requested shutdown, end app sessions and verify cleanup; stop
   only the known backend process/session. Never kill by process name.
