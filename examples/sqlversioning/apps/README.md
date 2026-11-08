# Local SQL versioning demo apps

Five light navy-and-silver presentation pages share a local Flask backend.
Presentation sizing is always on; there is no alternate mode or sizing toggle.
The Cowboys silver background and compact headings keep demo cards and the
first execution controls visible without scrolling on typical laptop screens.
Long step instructions and SQL expand on demand; destructive steps still require
confirmation. Template changes appear on browser refresh without restarting SQL
sessions or enabling Flask's process reloader.
SQL runs on your local SQL Server 2025 instance using your Windows account
and integrated authentication. No credentials, CDN, or cloud services are needed.

## Start

From this directory:

```powershell
.\start.ps1
```

The launcher reuses a healthy backend or starts one in its own console, verifies
readiness, and opens a **new normal Edge/Chrome browser window**. Keep that
console open. It does not execute setup or demo SQL. Use `-NoBrowser` only for
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

1. Check readiness on demo 0. Setup is **destructive**: the original setup
   script drops and recreates the three named lab databases and seeds data.
   Run it only after reviewing its SQL and confirming the prompt.
2. Select a demo and sub-demo, then run individual numbered steps.
   Read each step's SQL, explanation, and handoff before clicking.
3. Sessions 1 and 2 are independent, persistent SQL connections. Explicit
   transactions remain open across clicks. A blocked reader does not freeze
   the browser: advance the writer's commit step to release it.
4. Live DMV evidence, actual query results, error 3960, and DBCC PAGE output
   are shown separately from explanatory text. Result tables display at most
   1,000 rows. Version cleanup timing and internal page formats vary by build.
5. **End demo sessions** before switching demos or running database
   configuration steps. This cancels running work, rolls back unfinished
   transactions, and closes only this app's SQL connections.

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
first, then stop the Python server with Ctrl+C. Shutdown cleanup is best effort;
if the process is forcibly terminated, SQL Server rolls back disconnected sessions.

## Validate

```powershell
python -m unittest discover -v
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
