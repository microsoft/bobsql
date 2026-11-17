# Caldova Network Scheduling — Hyperscale Basics

Caldova Health's scheduling network on Azure SQL Database Hyperscale: **"Start here, stay here."**

Current readiness and the take-by-take recording order are in
[RECORDING-SCRIPT.md](RECORDING-SCRIPT.md). Measured Azure evidence is recorded below.

Caldova Health starts on one Hyperscale **serverless** database, then acquires two providers —
**Northbrook Family Clinics** and **Ridgeview Specialty Care** — and brings all three scheduling
databases into one **Hyperscale elastic pool**. Caldova staff can then find the next available
appointment anywhere in the network with one query, while storage grows without anyone declaring
files or sizes.

The app avoids the word "scheduler" for people (it collides with SQLOS schedulers); they are
**staff**.

## Two-part demo and guiding skill

Use the upstream [start-and-grow-hyperscale-demo](https://github.com/microsoft/sqlhyperscalemechanics/blob/main/.github/skills/start-and-grow-hyperscale-demo/SKILL.md)
for real deployment, database population, verification, and operations.
The repository skill contains operational guidance only; recording-specific
instructions are maintained separately outside the repository.
The [runbook](DEMO-RUNBOOK.md) is the presentation source of truth:

1. **Start with Hyperscale:** Azure Portal choices, Copilot-assisted requirements/
   sizing/deployment and change summary, then real SQL load and actual Azure
   Monitor CPU-used/billed-compute measurements.
2. **Grow without redesigning:** move the three providers into the existing pool,
   verify placement, scale pool compute while observing workload behavior,
   discuss connection retry handling as a talking point only, show actual database
   growth within the workload flow, then native cross-database search and booking.

Example prompts: "Build the start and grow demo", "Verify the start and grow demo",
"Run the start and grow demo", or "Start the grow chapter".
Creating the skill does not deploy resources or change the app.
The app still has the four-page navigation below. Independent chapter navigation
and pool scaling under workload observation are **not yet implemented**.
The skill defines their build and evidence gates; it does not simulate success.
Retry logic, retry instrumentation, and retry tests are not part of the build.

> **Current source implementation:** Step 1 uses real Azure Monitor data and an
> opt-in bounded SQL read workload, not the former scripted scene. Live
> scale-up/down and telemetry delay have not yet been verified. Steps 2 and 3 guide real pool operations in Copilot and
> the Azure portal. Step 4 executes native cross-database reads and a single
> provider write over synthetic scheduling data. SQL setup and live verification
> are required before publishing; there is no scripted appointment fallback.

## Live app

### Local pool scaling controls

**Growth presentation:** The explicitly selected local route
`/scale-presentation` uses `PoolPresentation__Enabled=true`. It animates gradual
CPU demand and Caldova's 18/20-GiB baseline using an in-memory model. It stops
as soon as the 20-to-30-GiB allocation callout appears, normally around sixteen
seconds, within the thirty-second maximum. Its controls never call Azure or SQL; each new take resets only that
model. Scale controls remain available during the run and do not restart its
clock or storage growth. Whole-core readings start at two and stay within the
selected pool capacity. The 24-vCore model uses a zero-to-twelve per-database cap
and unequal CPU demand: Caldova rises to twelve while the other schedules shift
independently, ending at twelve/seven/five. Each card shows shared capacity and
per-database minimum/maximum separately from CPU-used readings. At eight pool
vCores, the modeled cap is eight and consumption is shared within the total.
The final cards freeze at their unequal readings and Caldova
retains 30 GiB allocated until another take. There is no on-screen speed-up
caption or SQL-sampling claim. This is a
presentation illustration, not live proof. Step 4 navigation selects this
route only while the opt-in is enabled; `/scale` remains the separate real page.
With that opt-in, Network (`/verify`) uses the same circuit-scoped recording
capacity and limits as Scale, so navigating between the pages preserves the
selected eight- or twenty-four-core model. Demo screens omit playback,
illustration, and fictional-data notices for recording. `/verify-live` remains
directly accessible for independent real Azure inspection, without an on-screen link.
This cosmetic choice does not make modeled readings live telemetry or change
the synthetic provider data, mode selection, or operation safety gates.
With the opt-in disabled, Network continues to read real Azure resources.
Reloading the browser starts a new recording circuit at its default baseline.
Keep presentation disabled on public hosts. For recording, disable live
pool actions with `PoolScaling__Enabled=false` and `PoolGrowth__Enabled=false`.

Local verification: 376 offline checks pass without SQL connections, including
recording-state Network reads with Azure denied, explicit live inspection, and
unchanged behavior with recording disabled. Clean normal Edge verified repeated
Scale -> Network -> Scale navigation at eight, twenty-four, and eight again,
preserving matching shared capacity and minimum/maximum limits.
Earlier Edge rehearsal
verified 24 distinct CPU frames, initial two/two/two and final twelve/seven/five,
automatic completion on the first 20-to-30-GiB allocation frame, and min/max
changes during scaling under activity. The real ARM-backed Network page also
verified shared 24 and minimum zero / maximum twelve on all three cards.
Prior rehearsal verified scaling
under activity, the prominent callout, repeat takes, Stop, and
reduced-motion behavior. Expanded cards fit 1366x768, 1024x768, and 900x700
without scrolling. The real proof script passed its read-only preview and
approval guard; its live workload and growth have not been run for this change.

**Real off-camera proof:** Stop other real workload clients and preview
[13-rehearse-pool-growth.ps1](deploy/13-rehearse-pool-growth.ps1):

```powershell
.\startandgrowhyperscale\deploy\13-rehearse-pool-growth.ps1 -ExpectedServerName <network-server> -IncludeGrowth -WhatIf
```

After explicit approval, run without `-WhatIf` (`-Confirm:$false` only after
that approval). This uses the current CLI identity, existing objects, real
scheduling/CPU batches, and bounded Caldova payload inserts. It prints UTC SQL
CPU samples, query successes, actual storage readings, and measured peaks.
It refuses already-expanded storage and incomplete allocation growth rather
than claiming success. Omit `-IncludeGrowth` for CPU-only proof. Neither mode
books appointments, alters compute, sets up schema, or resets any database.
Presentation timing and real SQL execution time are separate evidence.

Step 4, Scale (`/scale`), offers **Scale Pool to 24** and **Scale Pool to 8**.
Each click authorizes one real server-side `az sql elastic-pool update`; there
is no additional confirmation. The command targets the existing configured
`caldova-network-pool`, keeps minimum zero, sets the per-database maximum to
12 at 24 pool vCores or 8 at 8 pool vCores, and waits for Azure. Both capacity
and limits are verified. The twelve-core cap allows unequal bursts without one
database consuming the entire 24-core pool; it is not an eight-core partition.
Both buttons are disabled during a scale and when capacity and cap already match.
All open Scale pages refresh their shared-capacity badges after verification.
SQL workloads, patient profiles, pool membership, server settings, and data
are not changed by these buttons.

**Run Scheduling** starts bounded read-only scheduling queries and CPU work on
all three pooled databases. Each starts two workers and adds two every five
seconds, reaching nine workers after twenty seconds. Nine workers target
approximately eight CPU-used vCores; this workload target is not a per-database
limit or consumption guarantee. Worker counts are not consumed cores.
These smaller ramp steps spread the rise across more of the sampling window.
Timing starts at worker launch, excluding connection startup. Pool batches run 100,000 scalar hash
iterations, down from the timeout-prone million-loop batches; Patient Access's
50,000 remains unchanged. Smaller batches return results sooner while concurrent
workers maintain CPU demand. These are worker counts, not allocated
cores or guaranteed consumption. The target is near 24 CPU-used cores; all
three workloads previously targeted approximately eight each, so usage
can converge briefly despite different ramps and holds. The cap policy allows
uneven demand; changing it does not itself revise or prove the workload curve. Moderately larger cards
show staff online, scheduling query counts, latest measured CPU values, and
simple storage bars. There are no CPU charts or full-page-height cards.
When measured Caldova allocation increases from the current run's initial
reading, a large **20 → 30 GiB**-style callout shows the actual before/after
allocation and added capacity. A brief card highlight draws attention to the
change; the callout remains after Stop and page reload, and respects reduced
motion. Already-expanded storage does not invent a new allocation event.
The DMV readouts show
each database's real CPU consumption, rounded up to whole cores; capacity is
not consumption. The header sums the three latest CPU averages before whole-core
rounding; missing or more-than-15-second misaligned samples show no total.
Stop cancels and joins all workload/observation; errors are
explicit and no scheduling query is retried. Activity stays running during a
scale operation. Scheduling queries perform no appointment bookings.
Only six workers start immediately, rather than twenty, so the first SQL sample
interval includes the rising load instead of beginning near full CPU usage.
Samples remain actual 15-second averages, not smoothed or interpolated values;
the revised CPU curve and near-24 peak still require live rehearsal.
The shared ramp's optional stopping-group override preserves symmetric grouping
for Patient Access and other callers that do not supply it.
Holds are 15 seconds with three workers stopping per five-second ramp-down
step. Profiles last 45 seconds each. The longest
profile plus 15-second observation cooldown is 60 seconds, excluding
startup and overrunning batches. Scaling and scheduling are offline-tested;
live behavior still needs rehearsal. 24-vCore regional support with 0–8 limits
has been verified read-only. Storage cards now measure actual used and allocated
ROWS-file space, excluding transaction logs. Each storage card shows actual used
and allocated GiB with a simple bar of used bytes divided by currently allocated
bytes. Allocation grows automatically; it is not the database maximum or a demo
fill target. There are no storage-history charts or numeric axes.
With `PoolGrowth__Enabled=true`, **Run Scheduling & Grow** also inserts synthetic Caldova payloads up to an
absolute ceiling of 21 GiB used and a 45-second
growth limit. Northbrook and Ridgeview are only measured. Observation continues
for 15 seconds after workload and
growth finish. Stop cancels and joins
inserts and refreshes measurements; committed batches remain. Intentional Stop
is normal cancellation, including SqlClient's "Operation cancelled by user"
error response, and does not show a false growth-failure alert. Unexpected
failures still surface explicitly. The demo's growth time budget ends inserts
normally, logs the stop, and refreshes actual committed space without replaying
writes. If growth past 20 GiB has not been confirmed, a neutral status says so; it is not
a successful growth confirmation. Failure to verify storage still surfaces.
Initial seeding continues to require its full target. Final verification can
add up to ten seconds before the observation cooldown. Growth finishes
as soon as SQL confirms Caldova used space above 20 GiB and allocation above
20 GiB, rather than continuing to chase 21 GiB after the allocation change.
If storage already meets that goal, the button reads **Run Scheduling** and
preserves existing storage. Subsequent Runs
do not reset data or write above the ceiling. The 2026-10-31 rehearsal reached
20.763 GiB used / 30 GiB allocated, but the old completion rule timed out while
still targeting 21 GiB. The revised early-completion rule and actual near-24
CPU peak still require live rehearsal; the allocation change itself is verified.
Scale uses moderately larger cards in three columns from 900 pixels wide,
retaining measured CPU values and storage bars; narrower windows stack the cards.
Pool CPU reads have a 30-second timeout under contention, while workers retain
their 15-second timeout and smaller batches. Failures identify CPU workload,
CPU observation, or storage observation; CPU readings publish before storage
inspection. No queries or writes are retried. The shorter scene remains a
planned duration, not a verified growth-throughput or CPU-peak guarantee.
For recording, pre-filling Caldova to 19.75 GiB used off camera is recommended
to reduce the on-camera inserts; that separate synthetic-data write requires
explicit approval and has not been performed. Initial seed targets remain 18/12/15.

**Isolated storage-reset evidence (2026-10-31):** A temporary Hyperscale database
in the existing 24-vCore pool completed two real allocation-growth/reset cycles.
Filler increased used space to 10.006/10.022 GiB and allocation from 10 to 20 GiB.
Truncating a separate growth table released pages within about five seconds;
manual `DBCC SHRINKFILE` returned allocation to 10 GiB in about 31 seconds.
Each complete reset, including baseline-row verification, took about 36 seconds
and preserved all 32,768 baseline rows (about 0.256 GiB used after shrink).
The temporary database was deleted and absence verified; the three demo
databases remained Online in the unchanged pool. This proves the mechanism on
a small baseline; the actual Caldova reset below is separate evidence.
A separate recording-growth table remains unimplemented.

**Grow recording reset:** Stop the local app and all dependent SQL workloads.
Preview [12-reset-demo-storage.ps1](deploy/12-reset-demo-storage.ps1), then obtain
explicit approval before applying:

```powershell
.\startandgrowhyperscale\deploy\12-reset-demo-storage.ps1 -ExpectedServerName <network-server> -WhatIf
```

The reset truncates only `demo.StoragePayload`, waits for page deallocation,
shrinks `data_0` toward 20 GiB allocated, then uses the existing bounded fill
procedure to restore 18 GiB used. It does not delete or recreate the database,
change appointments, or touch either server, other provider data, pool settings,
or preview enablement. Replacing the whole dummy baseline is necessary with the
current shared seed/growth table; this is not the faster separate-growth-table
reset tested above. Failures leave the verified partial state in place, stop
the operation, and require inspection rather than automatic replay.

**Actual reset verified (2026-10-31):** Caldova returned from 20.763 GiB used /
30 GiB allocated to 18.000 GiB used / 20 GiB allocated. The shrink phase took
about 26 seconds; the complete reset, including refilling the baseline and
verification, took about 4m12s. All 50 scheduling slots, zero appointments,
three provider-directory rows, non-demo object definitions, provider placement,
backup settings, and pool configuration were preserved.

Set `PoolScaling__Enabled=true` only for the localhost demo launched with
`ASPNETCORE_URLS=http://localhost:5099`; startup refuses public/wildcard bindings
when live scaling or growth is enabled. Leave both flags disabled for App Service.
Azure CLI must be installed and already signed in on the app host. The current
CLI subscription must match the monitored database's subscription; it is never
silently switched. Windows execution uses the installed CLI's Python entry
point with individual process arguments, not a shell command string.
Concurrent clicks across browser windows cannot submit duplicate operations.
Failures are displayed explicitly; interruption or timeout can leave an Azure
operation in progress and must be inspected before another attempt. No retries
or automatic rollback are performed.

### Initial Grow storage seeding

Off camera, seed actual used-data targets of Caldova **18 GiB**, Northbrook
**12 GiB**, and Ridgeview **15 GiB** before Step 4. This is Grow setup, not
Part 1 Patient Access population. All three databases must be Online in the
existing network pool. After approving these writes, run:

```powershell
.\startandgrowhyperscale\deploy\11-fill-demo-storage.ps1 -WhatIf
.\startandgrowhyperscale\deploy\07-deploy-scheduling.ps1 -Phase Storage
```

For a complete Grow schema seed on already-pooled databases, `-Phase Schema
-IncludeStorageFill` includes this same operation. The large fill stays opt-in;
ordinary Schema seeding is unchanged. Stop the local app before building.
The script uses the current Azure CLI identity/subscription and never switches.
It creates `demo.StoragePayload`, `demo.StorageSize`, and `demo.FillStorageBatch`,
with scoped grants to an existing app user. Up to 4096 uncompressed synthetic
rows are committed per batch; initial fills have a two-hour limit and cancel
sibling fills on failure. No scheduling rows are changed, and no data is
deleted, truncated, or shrunk. Reruns measure and fill only remaining space.
GiB means 1,073,741,824 bytes; allocated files can exceed the used-data target.
An interrupted write may have committed: inspect measurements before rerunning,
never replay blindly. CLI verification does not prove deployed-app SQL access.
Pool CPU observers, workers, and storage operations share an in-memory SQL token and serialize refreshes within
five minutes of expiry, avoiding repeated concurrent Azure CLI cache access.
Authentication errors still stop the run explicitly; no retry, sign-in,
credential-cache deletion, or unencrypted-cache fallback is performed.

The initial live fill on `<network-server>` is verified: Caldova
18.000, Northbrook 12.000, Ridgeview 15.000 GiB used, each with 20.000 GiB
allocated. Files grew from 10 to 20 GiB allocated during the fill. This proves
initial storage growth under the CLI identity, not Step 4 growth under CPU load
or deployed-app identity access.
After a rehearsal stopped on an Azure CLI decryption error, the shared pool-token
change passed 301 offline checks and two actual app read-only inspections of all
three databases. Caldova then measured 18.25 GiB used; Northbrook/Ridgeview remained
12.00/15.00. The partial committed growth was preserved, not reset or replayed.
This does not yet verify a complete workload/growth run.

Offline checks mock CLI execution and ARM responses:

```powershell
dotnet run --project .\startandgrowhyperscale\tests\CaldovaNetworkScheduling.Checks.csproj --configuration Release
```

The runner itself can be tested against the logged-in account without mutation:

```powershell
dotnet run --project .\startandgrowhyperscale\tests\CaldovaNetworkScheduling.Checks.csproj --configuration Release -- --pool-cli-check
```

### Published serverless illustration

The updated package is published to the existing App Service. Launch
`https://<network-app>.azurewebsites.net/serverless-illustration`
for the approved, explicitly labeled scripted scene.
The measured page remains at `/`; these are two routes of one deployed app.
`Demo__Mode=Measured` is the startup compatibility setting, not a claim that
the illustration route uses real telemetry. Live SQL load generation is
explicitly disabled.

The deployed interactive scene passed an Edge browser check: start at 1.00,
rise to 4.00, fall to 1.00, scripted pause at zero, resume above zero, reset,
and return to the measured view. No browser errors were observed.
All six page/liveness endpoints returned HTTP 200, and 74 offline contract/
component checks passed. These checks do not establish application SQL access,
real four-vCore usage, or visual rehearsal of the authenticated Azure portal.
Historical billing and pause/resume evidence is documented below; the portal
bar chart still requires the presenter to set and verify the intended view.

| | |
|---|---|
| URL | `https://<network-app>.azurewebsites.net` |
| Resource group | `caldova-network-rg` (currently signed-in Azure subscription) |
| App Service | `<network-app>` on Windows S1 plan `asp-caldova-network-<suffix>`, East US 2 |
| Logical server | `<network-server>.database.windows.net` — **East US 2**, Microsoft Entra-only auth, public endpoint + firewall |
| Elastic pool | `caldova-network-pool` — Hyperscale, 8 vCores, on the same logical server; **empty** for now |
| Databases | `caldova-scheduling` (serverless `HS_S_Gen5_8`, 1–8 vCores, auto-pause 60 min), `northbrook-scheduling` (provisioned `HS_Gen5_2`), `ridgeview-scheduling` (provisioned `HS_Gen5_4`) — all standalone |

The table describes the original standalone baseline. Use `05-verify-sql.ps1`
or the Azure portal for current placement. Source changes are not automatically
published to the live app.

Scripted backup clips of every app sequence come from playback mode; see
[Playback mode and backup clips](#playback-mode-and-backup-clips).

## Pages

The top navigation is numbered in story order.

| Nav | Beat | What it shows |
|---|---|---|
| **1 · Patient Access** (`/`) | Start here | Run starts SQL load and DMV observation; the chart shows CPU used from 15-second SQL resource stats. **Behind the chart** shows the workload SQL and raw samples. Billing is shown separately in the Azure portal (no in-app button). |
| **2 · Acquisitions** (`/network`) | Bring providers together | Starting-configuration cards only. The pool move happens in Copilot (skill), not in the app. |
| **3 · Network** (`/verify`) | One pool, one network | Cards per database (pool, three-part name, open slots). **Check network** runs the cross-database view from Caldova and shows the query. Pool membership is shown in the Azure portal (no in-app button). |
| **4 · Search & Book** (`/appointments`) | Stay here | Compare Caldova-only and network searches. Read a native cross-database join view, then book in one transaction from Caldova that updates the slot and inserts an appointment, both in the provider's database. |

## Measured serverless chapter

### Save a live run, then replay it for recording

Patient Access defaults to live SQL. You can optionally save a completed **Run**,
restart the app in saved-run mode, and use the same **Run** button to play that
capture faster. This is separate from the older synthetic `Demo:Playback`
backup mode: saved runs use your original DMV samples and captured UI frames,
not generated CPU readings.

The page intentionally has no playback or speed badge. A recording made in this
mode is a **time-compressed replay of an earlier measured run**, not a new
real-time Azure measurement. Describe it accordingly when presenting or sharing
the video. Staff, counters, illustrative patient activity, CPU, and chart history
all advance on one source-time clock. CPU values, timestamps, gaps, and ordering
are retained without interpolation. Patient rows visualize the CPU workload;
they are not appointment writes.

**1. Capture live.** From the repository root in PowerShell, verify that the
`part1` connection and monitor settings target your intended Start database.
Use the normal setup, Entra permissions, and live-workload approval first.
The profile enables real SQL work; connecting can resume compute, incur charges,
and restart the auto-pause idle period.

```powershell
$env:Demo__Playback = "false"
$env:ServerlessRecording__Mode = "Live"
$env:ServerlessRecording__File = Join-Path (Get-Location) ".artifacts\caldova-serverless-run.json"
dotnet run --project .\startandgrowhyperscale\app\CaldovaNetworkScheduling.csproj --configuration Release --launch-profile part1
```

Open `http://localhost:5099/` and click **Run**. Leave the tab connected until
the run completes and the console reports **Saved completed serverless Run**.
The live screen has no elapsed header clock. The restored Run control and the
saved-completion log identify that capture has finished.
The current plan is 195 seconds plus startup and in-flight SQL time. A complete
file includes the trailing CPU observation. Stop, failure, tab disposal, or
save cancellation does not replace the previous good file. Save errors appear
on the page and in the console; do not assume completion of SQL work proves
that a capture was saved.

Captures are written atomically outside `wwwroot`; the `.artifacts` location
above is ignored by Git. They contain raw CPU samples and displayed scene
frames, including synthetic patient names, but no connection strings, tokens,
subscription IDs, or tenant IDs. Review any capture before sharing it.

**2. Restart using the saved run.** Stop the local host with Ctrl+C, then run:

```powershell
$env:Demo__Playback = "false"
$env:ServerlessRecording__Mode = "Replay"
$env:ServerlessRecording__File = Join-Path (Get-Location) ".artifacts\caldova-serverless-run.json"
$savedRun = Get-Content -LiteralPath $env:ServerlessRecording__File -Raw | ConvertFrom-Json
$env:ServerlessRecording__Speed = ([double]$savedRun.frames[-1].elapsedSeconds / 30).ToString("R", [Globalization.CultureInfo]::InvariantCulture)
dotnet run --project .\startandgrowhyperscale\app\CaldovaNetworkScheduling.csproj --configuration Release --launch-profile part1
```

Refresh `http://localhost:5099/` and click **Run**. The calculated speed targets
30 seconds of playback using the complete capture's actual duration, not its
planned duration. For a slower presentation, divide by 75 instead of 30.
The resulting speed must remain within the supported 0.25-10 range.
Live and replay hide the header elapsed clock. Sample/activity times retain original
source time, not wall-clock playback time. Before the first saved CPU sample,
the readout and gauge start at zero with no pending label. Staff, patient rows,
and counters stay at their empty initial view until the first aligned CPU frame.
This hides any newer, unaligned startup previews in older captures, preventing
rows or counters from jumping backward when the first CPU sample arrives.
The original saved data remains unchanged. New live captures use the same
startup gating. The activity-status
line follows staff signing in, working, and signing out as the left-hand
activity changes; it contains no CPU-waiting message. Once staff reaches zero,
the sign-out phase continues until measured CPU reaches zero; only then does
it say everyone has signed out. During that trailing interval, the left staff
header also says **Staff signing out** instead of showing a zero staff count;
the real zero count returns when CPU reaches zero. Neither CPU readings nor
staff counts are changed.
This placeholder is
not inserted into the saved measurements or chart. **Stop** pauses, **Run** continues, and **Reset**
returns to the beginning. Run after completion starts the same capture again.
Speed can be 0.25-10; change the setting and restart to try another speed.

The serverless replay path does not poll ARM, connect to SQL, generate load,
resume compute, or change any Azure resource. Its live **Sign in (resume)**
control is hidden. Missing, malformed, incompatible, or incomplete capture files
stop startup explicitly; there is no fallback to live SQL or synthetic data.
`/healthz` reports `mode: replay` and `serverless: saved-sql-dmv` for operational
verification. Other app chapters remain separate, potentially live operations;
do not navigate to them assuming they use this capture.

This capture covers the morning **Run**, not the hour-long auto-pause wait,
first-sign-in resume, Azure Monitor billing, or Grow scenes. Those remain real,
separately approved operations in live mode.

**3. Return to live.** Stop the host, set
`$env:ServerlessRecording__Mode = "Live"`, and remove
`ServerlessRecording__File` from the process environment if you do not want
to capture another run:

```powershell
$env:ServerlessRecording__Mode = "Live"
Remove-Item Env:\ServerlessRecording__File
dotnet run --project .\startandgrowhyperscale\app\CaldovaNetworkScheduling.csproj --configuration Release --launch-profile part1
```

The existing saved file is retained. Capture/replay settings do not deploy,
populate, reset, or reconfigure a database.

### Presentation focus: billed compute

The current presentation goal is a real Azure Monitor **bar chart** showing
billed compute near the 1-vCore online minimum, above it during activity,
back toward the minimum afterward, no compute charge during confirmed auto-pause,
and billing returning after resume. CPU-used/memory comparisons are diagnostic
detail, not a required portal presenter beat. The app still targets approximately
four CPU-used vCores and a ramp back down. Real achievement remains unproven;
the explicit scripted fallback now peaks at 4.00 and has passed a complete
Edge playback test (rise, fall, pause, resume, reset, return to measured view).
Historical experiment results below remain unchanged.

For average billed vCores, transform `app_cpu_billed` **Sum** from vCore-seconds
by dividing by the bucket duration in seconds in an Azure Monitor workbook.
Raw Metrics supports Sum, not Average, for this metric. With one-minute
granularity, 60 vCore-seconds is equivalent to 1 average billed vCore.
Use bars and accurate units; do not relabel raw Sum as vCores.

The rise/fall tests below do not constitute a single full pause/resume recording.
Close all SQL clients/workload connections and wait for actual auto-pause after
the configured 60-minute idle delay. Use ARM status/activity evidence to identify
the paused interval, not missing metric samples alone. A paused interval has no
compute charge, but missing samples must not be silently converted into zeros.
Record/time-lapse the real timeline as needed; separately approve the connection
that resumes the database. No live changes are implied by this presentation plan.

Configuration is under `ServerlessMonitor` in [appsettings.json](app/appsettings.json).
`Demo:Mode` must be `Measured`; there is no automatic scripted fallback.
The measured view has an explicit **Scripted illustration (fallback)** link to
`/serverless-illustration`, with persistent scripted labels and a return link.
It uses the original scripted workload only on that page; it never feeds
invented samples into the measured chart or runs SQL.

1. **Published 2026-10-23 (`/healthz` reports `sql-dmv`):** the app uses
   `sys.dm_db_resource_stats`, not Azure Monitor, for its CPU chart.
   ARM configuration is still read with `DefaultAzureCredential` to validate
   the standalone Hyperscale serverless target and display its configured range.
2. The observing identity needs Azure database-resource read access plus SQL
   access with `VIEW DATABASE STATE`. No permissions are granted automatically.
   Local diagnostic identity success does not prove the App Service identity
   has these permissions.
3. Click **Observe SQL CPU** only after approval for compute usage. Observation
   connects through `ConnectionStrings:Scheduling`, validates the exact
   primary database target, disables pooling/retries, and closes each poll's
   connection. Polling can resume compute and prevents auto-pause.
4. Polling reads primary-replica samples approximately every 15 seconds.
   The SQL DMV retains approximately an hour; the observation window is limited
   to 55 minutes. UTC timestamps are **interval ends**, not minute starts.
   Actual zeros remain zero; missing intervals are not generated or zero-filled,
   and chart lines break across gaps. Errors stop observation and workload.
5. **CPU used (average vCores)** =
   `avg_cpu_percent * cpu_limit / 100`, using each SQL sample's own limit.
   The raw percentage, limit, timestamp, and calculated value appear in the
   table. With a limit of 8, 50% is 4 average CPU-used vCores. This does not
   measure allocated cores or billed compute.
6. Billing stays in the portal. Show bars without hovering. `app_cpu_billed`
   Sum is vCore-seconds; divide by bucket seconds only when a workbook needs
   average billed vCores. No Azure Monitor CPU data feeds the app chart.
7. Before generating load, approve the target and cost, and restrict access to
   the demo app. Set `ServerlessMonitor__EnableWorkload=true` only in that
   approved environment. It is false by default; deployment does not enable it.
   Observation also executes SQL, so restrict access before exposing a
   managed-identity-enabled instance.
8. Click **Start SQL workload** with 1-16 workers for 1-10 minutes. The current
   synthetic CPU workload repeatedly hashes a scalar `varbinary(32)` value
   50,000 times per batch using `SHA2_256`. It accesses no tables, uses no joins
   or sorts, and requests no deliberate table-sized working set. It does not
   fabricate bookings, write data, or guarantee a particular CPU/billing curve. The SQL
   connection must match the monitored resource. Real load can resume the
   database and incurs charges. A worker error stops all workers with no retry.
9. Stop load and continue observing actual CPU behavior. Workers close
   their connections on stop; SQL observation continues until explicitly stopped. Leaving the
   page/disposal stops its circuit-scoped workload, and the duration limit
   bounds work even if a disconnected circuit is retained temporarily.
10. Stop **observation** and all other SQL clients before waiting for auto-pause.
    CPU-used zeros do not imply zero billed compute while online. A tiny scalar
    working set does not eliminate engine/session memory or guarantee CPU-only
    billing. Do not flush caches or change configuration to force chart values.

Record/time-lapse if needed, retaining UTC timestamps and labeling the recording
as time-lapsed. No sped-up app clock, extrapolated points, snapped vCore values,
or assumed pause. First prove workload intensity, visible rise/fall, and actual
metric delivery delay against the target; this source implementation is not
evidence that all live checks have passed. See the bounded live result below.

### Live result - 2026-10-22

#### SQL DMV diagnostic revision (latest)

The approved unchanged 16-worker scalar run on October 22 used SQL DMVs rather
than Azure Monitor for CPU measurement. It was bounded to three minutes but
stopped early after a SQL command timeout (`-2`): **257 completed batches,
one reported failure, no retry**. This is not a completed three-minute test.
All workload and diagnostic connections were disposed.

Read-only capture of retained primary-replica resource statistics confirmed:

| UTC interval end | CPU % | SQL vCore limit | Average CPU-used vCores |
|---|---:|---:|---:|
| 18:19:27.020 | 0.00 | 8 | 0.0000 |
| 18:19:42.060 | 2.44 | 8 | 0.1952 |
| 18:19:57.087 | 39.40 | 8 | 3.1520 |
| 18:20:12.113 | 6.33 | 8 | 0.5064 |
| 18:20:27.153 | 0.00 | 8 | 0.0000 |

The DMV path proves a real CPU rise and decline, **not approximately 4 vCores
or a successful full workload run**. One live session snapshot saw all 16
workload sessions, with a preceding session CPU delta averaging 0.9678 vCores;
it does not cover the later peak interval. Most sessions were sleeping in that
snapshot. The timeout's cause is not established. The failure exited before
the original harness printed its wait summary; no workload wait-delta
conclusion can be drawn from this run.

The harness now retains cooldown and wait summaries even when a workload
reports a failure, then exits nonzero. No second load run was performed.
The read-only `--serverless-dmv-observe-from <UTC timestamp>` path retrieves
retained SQL samples without starting workers; it still connects to SQL and
requires compute-use approval. `--serverless-live --serverless-workers 16`
uses a 30-second SQL baseline, at most three minutes of load, and a 60-second
SQL cooldown. ARM is used for target validation only, not Azure Monitor metrics.
Historical `--serverless-observe-from` remains management-only.

#### 16-worker repeat from an Azure client (2026-10-22 evening)

The unchanged 16-worker run was repeated from a West US 3 Windows 365 Cloud PC
(the database is in East US 2). It **completed the full three minutes** with
4,236 batches, 0 failures, and no timeouts. DMV CPU-used vCores rose from 0 to
5.86 in the first interval, held **7.97-7.99 (99.6-99.9% of the 8-vCore limit)**
for ten consecutive intervals, then returned to 0.00 in the first cooldown
interval. The top database wait delta was `SOS_SCHEDULER_YIELD` (1,381 s, nearly
all signal wait); `ASYNC_NETWORK_IO` was 4.4 s. This shows CPU saturation at the
configured maximum, not the earlier timeout's cause. The all-at-once start/stop
produced a step, not a gradual ramp.

#### Staged ramp (harness measured; app page not yet run live)

`--serverless-live --serverless-ramp` starts one worker per step, holds at the
peak, then stops one worker per step (last started first; each finishes its
in-flight batch, no command is cancelled). Defaults: peak 8 workers
(`--serverless-workers`), `--serverless-ramp-step-seconds 30`,
`--serverless-ramp-hold-seconds 60`, giving 0 -> 8 -> 0 over 8 minutes
(total limited to 10 minutes). The harness logs active workers alongside DMV
samples. These harness defaults are unchanged.

The Patient Access page uses a separate **195-second planned Run** with explicit
worker levels: 1 at startup, 2 at 15 seconds, 6 at 30 seconds, and 10 at 45 seconds.
After a 60-second peak hold, two workers stop every 15 seconds: 8 at 105 seconds,
6 at 120, 4 at 135, 2 at 150, then zero at 165 seconds. Workers finish their
in-flight batches. Ramp-up remains 45 seconds; sign-outs span 60 seconds.
Ten concurrent workers target the eight-vCore database cap without the long
saturated sign-out plateau seen with 16 workers. The staff display honestly
shows those workers, not eight simulated staff.
Verify that an actual capture reaches the desired CPU peak and declines before
using it for recording; the workload schedule alone is not measured proof.
Another 30 seconds observes trailing SQL samples. Startup and in-flight batches
can add time; late telemetry may not include a final zero within this window.
The separate resume sequence holds four workers until manual Stop, without a
sign-out phase. It retains a ten-minute workload safety limit. Azure auto-pause
remains 60 minutes. The 195-second timing is offline-tested; its real peak,
sample delivery, and decline still require live verification.

Staff avatars, activity, and sign-in/sign-out status use recorded worker
observations at the displayed CPU interval's midpoint, not the current
wall-clock stage. The presentation omits the interval/staff explanation line;
raw samples remain available behind the chart. During live activity, Stop
remains available, including trailing CPU observation. Internal elapsed tracking
freezes when activity completes, stops, or fails, but no header clock is shown.
Reset clears it; a new Run starts over, while resume activity preserves its existing origin.
Worker counts are observed every
half second. Illustrative patient rows and counters advance at that cadence
while actual SQL batches complete, and their full historical frame is retained
with each observation. The CPU display selects that frame rather than generating
patient activity once per 15-second sample. New staff can therefore appear
working within their first displayed interval. These are workload visuals,
not actual appointment writes. Stopped CPU readings are labeled as the last
recorded value, and the schedule as recorded activity. A normally completed
live run instead retains the same schedule heading, CPU label, and completion
message as replay; the live scene continues watching Azure management state
for auto-pause without starting more SQL work.
Staff counts are not CPU-used vCores, and a 15-second average may
span a transition; exact 1/2/6/8 CPU readings or matching CPU direction at every
step are not guaranteed. Missing intervals are never filled or synthesized.
During post-resume load, staff and scheduling rows instead follow current
connected workers and completed batches, so scheduling begins without waiting
for the first 15-second CPU interval. CPU readings still retain their original
sample timestamps; staff counts are not inferred from CPU usage.

After sign-in, the app focuses the CPU plot on a separate initial 60-second resume
window, including 30 seconds of real baseline. Four-worker workload continues
until manual **Stop**, with a ten-minute safety limit; the chart extends if needed.
The first signing-in staff member remains visible while workers connect; badges
then follow connected workers without flashing back to zero or being held at one.
Once online, the schedule pane shows only scheduling rows from completed activity,
not staff-count or status-message placeholders. Its patient rows are demo visuals,
not real patient data or appointment writes.
Manual Stop ends the workload and telemetry and holds the last verified
four-staff interval. The held frame keeps the normal **Active**, **4 staff online**,
**Live schedule**, and **vCores in use (CPU)** appearance, without a completion
banner or recording labels. There is no resume sign-out or trailing-observation
phase. This is a held frame for the recording, not continued workload or telemetry;
four workers do not imply four vCores. Stop before a verified four-staff CPU
interval returns the ordinary stopped view rather than inventing an ending.
Reaching the safety limit without manual Stop reports an explicit error.
This keeps the resume curve readable after a long pause
instead of squeezing it against the right edge of a morning-to-evening chart.
Earlier samples and their original timestamp gaps remain in the raw history;
they are excluded only from the focused plot. No pause samples are invented.
Reset or a new Run clears the resume window.

The CPU gauge uses numeric hash marks at 1, 2, 6, and 8 for the 1-8-vCore
configuration. Marks and fill share the same CPU-used scale: six used vCores
reach 75% of the eight-vCore bar. The configured compute range is labeled
separately; CPU measurements below one remain unchanged.

The approved harness ramp from the same Cloud PC (SQL start 00:45:40, stop
00:53:40 UTC on 2026-10-23) completed **7,647 batches with 0 failures**. DMV
CPU-used vCores rose almost monotonically from 0.38 to 5.89 during the ramp
up, held 6.17, 6.09, and **6.94 (peak)** at 8 workers, fell from 5.99 to 0.81
during the ramp down, and reached 0.00 in the second cooldown interval. That is
about 0.75-0.87 vCores per worker; `SOS_SCHEDULER_YIELD` fell to about 200 s
(versus 1,381 s for 16 workers). Bob accepted the 6-7 vCore peak, so 8 workers
remains the default. This is one run from one client; the app-page ramp and
App Service publication are separate unverified gates.

#### Unified Patient Access page, pause, and resume (source; local only)

Patient Access (`/`) is the measured page with a single **Run** button; the
scripted illustration has no on-page button and is reached only by URL
(`/serverless-illustration`). Both render the same
staff avatars, KPI tiles, live schedule, and vCore panel. In Measured mode,
staff online equals the actual number of active SQL workers, schedule entries
are labeled illustrative and advance only while SQL batches complete, and the
readout/gauge/chart use only SQL DMV samples.

Outside a run, Measured mode reads the database's Azure management status every
10 seconds (no SQL connection, so it does not prevent auto-pause) and shows
**Paused** or **Resuming**. **Sign in (resume)** opens one read-only connection
(`SELECT 1`) and automatically retries documented transient errors such as
40613 with capped backoff for up to three minutes, then reports the elapsed
time. Hyperscale's minimum auto-pause delay is **60 minutes**; close all SQL
clients (app runs, VS Code MSSQL, SSMS, portal query editor) at least about
65 minutes before the pause beat. This page has not yet completed a live
resume, and is not published.

On 2026-10-23 a measured app run (15 s up / 60 s hold / 45 s down) started at
about 16:23:40 UTC and closed its last SQL connection at about 16:33:25 UTC.
With no other clients, the Activity Log recorded a successful auto-pause at
**17:34:34 UTC** (about 61 minutes later), and the measured page displayed
**Paused** from Azure management status without opening a SQL connection.
**Sign in (resume)** then woke it: the Activity Log recorded a successful
resume at **18:44:05 UTC**, and per-minute `app_cpu_billed` returned to about
60 vCore-seconds (the 1-vCore minimum). The portal chart shows billing before
the pause, no billed values from 17:36 through 18:44, and billing again
from 18:45 (56.517 vCore-seconds, then about 60 per minute). The 17:35 bucket held 14.069 vCore-seconds as the pause completed.
Azure Monitor reports no value for paused minutes, not zero.

The app's measured chart has been changed in source to this DMV measurement.
All offline checks pass (**96** after the staged-ramp change). A read-only live check of the actual app
telemetry service returned **30 primary-replica samples**, including the
3.1520-vCore peak, using the diagnostic identity. No second load run was used.
On 2026-10-23 the DMV/ramp revision was published with `02-publish-app.ps1`;
`03-verify.ps1` passed and `/healthz` reports `"serverless":"sql-dmv"`.
App settings were unchanged (`ServerlessMonitor__EnableWorkload=false`, public
access). The scripted fallback is unchanged. App Service SQL permission and
readiness remain a separate, unverified gate.

#### Confirmed historical pause/resume

Management-only inspection found successful Activity Log records for:

- Auto-pause: **2026-10-21 20:54:22 UTC**.
- Auto-resume: **2026-10-22 16:01:41 UTC**.

Actual `app_cpu_billed` Sum at 15-minute granularity:

| UTC bucket start | Billed vCore-seconds |
|---|---:|
| October 21 20:00 | 905.52 |
| October 21 20:15 | 889.37 |
| October 21 20:30 | 905.49 |
| October 21 20:45 (partial before pause) | 599.97 |
| October 21 21:00 through October 22 15:45 | No samples |
| October 22 16:00 (includes resume) | 759.40 |
| October 22 16:15 | 1069.67 |
| October 22 16:30 | 1572.23 |

Values are illustrative rounded summaries of actual returned buckets; the paused
interval is confirmed by Activity Log, not inferred solely from missing samples.
Use **October 21 19:45 through October 22 16:45 UTC** for a historical bar
overview and zoom to the later measured rise/fall window below. Show the bars,
not hover tooltips. These management results do not claim that portal chart
rendering or a saved workbook has been visually rehearsed.

No new SQL connection, cache flush, compute change, or resume was used to collect
this historical evidence.

Approved test: same standalone 1-8 vCore database, four workers, three minutes,
read-only, no retries or Azure configuration changes. The stronger query
completed **1,659 reads with zero reported SQL failures**, from
**16:20:37.898 to 16:23:38.065 UTC**. The following actual Azure Monitor buckets
were captured afterward (one-minute granularity, maximum 8 vCores):

| UTC minute start | CPU % Average | CPU used, vCores | Billed Sum, vCore-seconds | Billed average vCores |
|---|---:|---:|---:|---:|
| 16:20 | 0.03125 | 0.0025 | 59.467 | 0.99112 |
| 16:22 | 13.21875 | 1.0575 | 127.209 | 2.12015 |
| 16:23 | 13.15625 | 1.0525 | 127.828 | 2.13047 |
| 16:25 | 0.07142857 | 0.00571429 | 59.466 | 0.99110 |

This proves a visible measured usage/billing rise and fall, not allocated-core
telemetry. It does **not** meet the ideal of CPU used exceeding 2 vCores for two
complete minutes. The app UI, deployed managed identity, and portal/workbook
visualization still need end-to-end rehearsal. Nothing was published.
Most-recent buckets were missing or revised as data arrived: the 16:25 billed
Sum increased from 45.347 to 59.466 on a later read. Do not treat the newest
clock-complete bucket as final or interpret missing values as zero.

#### Follow-up: 16 workers, same query

Approved follow-up changed only concurrency from four to 16, keeping the same
query, standalone 1-8 vCore configuration, and three-minute load limit.
SQL ran **16:35:38.336-16:38:38.788 UTC**, completing **2,990 reads with zero
reported SQL failures**. Workers stopped before the management-only cooldown.
Later captures returned:

| UTC minute start | CPU % Average | CPU used, vCores | Billed Sum, vCore-seconds | Billed average vCores |
|---|---:|---:|---:|---:|
| 16:35 | 0.046875 | 0.00375 | 60.468 | 1.00780 |
| 16:37 | 31.390625 | 2.51125 | 298.709 | 4.97848 |
| 16:38 | 31.40625 | 2.51250 | 304.227 | 5.07045 |
| 16:39 | 21.078125 | 1.68625 | 226.508 | 3.77513 |
| 16:40 | 0.125 | 0.01000 | 60.497 | 1.00828 |
| 16:41 | 0.125 | 0.01000 | 60.458 | 1.00763 |

This meets the earlier >2 CPU-used vCore threshold in two consecutive buckets
and shows a decline, but **does not meet the newer approximately 4 CPU-used
vCore target** (about 50% of the 8-vCore maximum). Billed compute near 5 vCores
is not CPU used near 5 vCores. Do not claim linear scaling from worker count or
invent a cause for the remaining gap without diagnostics.

#### Small-working-set revision and validation

Before changing the join query, actual `app_memory_percent` for the
16:35-16:43 UTC test was retrieved: one-minute averages were approximately
**8.50-8.81%**, with maxima approximately **9.42-9.56%**. These percentages
do not establish why billed compute exceeded average CPU used. That gap must
not be described as proven memory-driven billing.

The current source replaces the join query with the bounded scalar hash batch
described above and captures memory beside CPU and billing. An approved
16-worker, three-minute test started at **2026-10-22 17:08:40.705 UTC**.
It completed **38 batches**, then reported SQL login transport error **10053**:
"An established connection was aborted by the software in your host machine."
The harness canceled workers, disposed their connections, and exited without
retry. The error occurred during login to the redirected SQL endpoint, not as
a reported query memory error. Its root cause is unproven.

That first attempt was **not** a completed scaling test.
An explicitly approved unchanged repeat ran **17:18:52.393-17:21:53.964 UTC**,
completing **1,891 batches with zero reported SQL failures**. A later
management-only refresh captured:

| UTC minute start | CPU used, vCores | Billed average vCores | App memory %, Average |
|---|---:|---:|---:|
| 17:18 | 0.00500 | 1.00848 | 8.50537 |
| 17:20 | 0.58500 | 1.38783 | 8.49414 |
| 17:21 | 0.81750 | 1.63983 | 8.49658 |
| 17:22 | 0.79000 | 1.67095 | 8.49561 |
| 17:23 | 0.00625 | 1.00977 | 8.50000 |
| 17:24 | 0.00500 | 1.00960 | 8.52393 |

The scalar query executes successfully with nearly flat app memory percentage,
but **does not meet the four CPU-used vCore target** and produces less measured
CPU load than the previous join workload. Different achieved CPU demand means
this is not proof of memory-related cost savings. The billing/CPU gap remains
unexplained by these observations. Do not promise CPU-only billing or repeat
load tests without an evidence-driven diagnostic hypothesis.
The previous join-workload window remains the stronger presentation evidence.
The MSSQL extension currently exposes no connection profile for this Caldova
server, so query-plan/resource-governance diagnostics have not been executed
through that diagnostic path. No cache flush, firewall, capacity, role, or
retry-policy change was made. All load workers stopped and connections were
disposed; subsequent observation used management APIs only. Source changes
were not published.

The preferred portal rehearsal window remains **2026-10-22 16:35-16:43 UTC**
(11:35-11:43 CDT); the earlier window above remains valid historical evidence.
On the actual Caldova database, use **Monitoring > Metrics**:

- Chart 1: **App CPU percentage**, **Average**, one-minute granularity.
- Chart 2: **App CPU billed**, **Sum**, same time range and granularity.
- Diagnostic chart: **App memory percentage**, **Average**, same window.
- Keep raw units explicit, or transform both into average vCores in a workbook.
  Do not overlay percent and vCore-seconds as equivalent units.

If using the scripted illustration, still show these actual portal charts.
State that their historical window is independent of the illustration's clock;
the illustration does not generate or prove the charges. Choosing fallback is
an explicit presenter action, never an error-triggered success substitute.

The existing approved live-check harness is
[ServerlessLiveCheck.cs](tests/ServerlessLiveCheck.cs).
`--serverless-live` incurs real compute usage and requires new approval for
each run. It defaults to four workers; use `--serverless-workers 16` only when
that concurrency is explicitly approved (accepted range 1-16; duration remains
three minutes). `--serverless-ramp` replaces the fixed run with the staged
0 -> peak -> 0 schedule described above and also requires per-run approval.
`--serverless-observe-from <UTC-minute>` performs management reads
only; use it only for a window whose configured maximum was already recorded.
No automatic booking test is part of either mode.
`--serverless-dmv-observe-from <UTC timestamp>` instead performs SQL reads of
retained primary-replica intervals and verifies the app telemetry service.
It starts no workers but requires approval for SQL compute use; it is not a
management-only or auto-pause-safe observation mode.

Official references:
[serverless monitoring](https://learn.microsoft.com/azure/azure-sql/database/serverless-tier-monitor),
[SQL resource statistics](https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-objects/sys-dm-db-resource-stats-azure-sql-database?view=azuresqldb-current),
[supported metrics](https://learn.microsoft.com/azure/azure-monitor/reference/supported-metrics/microsoft-sql-servers-databases-metrics),
[metrics REST API](https://learn.microsoft.com/rest/api/monitor/metrics/list).

## Platform facts

Verified against Microsoft Learn on 2026-10-15:

- Hyperscale serverless `HS_S_Gen5_8` scales between **1 and 8 vCores**; max data size **128 TB**
  ([resource limits](https://learn.microsoft.com/azure/azure-sql/database/resource-limits-vcore-single-databases)).
- CPU consumption is measured rather than inferred from signed-in staff.
  The app does not infer runtime scaling increments or snap measurements.
  Usage is metered per second
  ([billing](https://learn.microsoft.com/azure/azure-sql/database/serverless-tier-billing)).
- Billed compute includes CPU, memory, and a configured minimum. Do not infer
  its fall time from CPU alone; show the measured series.
- Hyperscale serverless **auto-pause is in preview**; the default and **minimum delay is 60 minutes**;
  named replicas aren't supported with auto-pause
  ([auto-pause](https://learn.microsoft.com/azure/azure-sql/database/serverless-tier-auto-pause-resume)).
  The live demo can't pause on camera — show a pre-recorded pause later.
- **Auto-resume**: the first connection to a paused database starts the resume; that attempt fails
  with error 40613 and the app must retry. Databases generally resume in less than one minute
  ([auto-resume troubleshooting](https://learn.microsoft.com/azure/azure-sql/database/serverless-tier-auto-pause-resume#auto-pause-troubleshooting)).
- **Serverless is single-database only**; elastic pools use provisioned compute. Moving Caldova into
  the pool *is* the upgrade from serverless to provisioned
  ([serverless overview](https://learn.microsoft.com/azure/azure-sql/database/serverless-tier-overview)).
- Moving a database into a Hyperscale elastic pool requires matching zone-redundancy and backup
  storage redundancy settings
  ([Hyperscale elastic pools](https://learn.microsoft.com/azure/azure-sql/database/hyperscale-elastic-pool-overview)).
- Native cross-database private preview (onboarding supplied 2026-10-21; guide saved in
  [docs/crossdb-private-preview.md](docs/crossdb-private-preview.md)): three-part
  names across online databases on the same logical server and supported elastic pool.
  Microsoft Entra authentication requires a server login and users mapped from that
  login in each database, with object permissions in each. Reads can span databases;
  each transaction can write to only one database. Savepoints are not supported.
  This replaces the earlier elastic-query/external-table plan. The app uses this
  path after the SQL setup below is deployed.

## Application data paths

The UI keeps the serverless chapter separate from the SQL appointment workflow:

| Interface | Implementation | Data source |
|---|---|---|
| `ServerlessMonitor` / `ServerlessSqlWorkload` | Azure Monitor REST / bounded SqlClient workers | Actual one-minute CPU/billing observations and real read workload; no scripted default |
| `IAppointmentAvailabilityService` | `SqlAppointmentAvailabilityService` | One source connection to `caldova-scheduling`; join-view reads and provider-specific conditional updates |

`network.AppointmentAvailability` joins Caldova's central `network.ProviderClinic`
directory to each provider's `dbo.AppointmentSlot` table using three `LEFT JOIN`s
guarded by provider key and clinic ID, without a union. Only one schedule can
match each directory row; `COALESCE` selects that schedule's appointment fields.
Rows with no matching unbooked slot are excluded. Only network members and unbooked
slots are exposed; searches filter to future UTC slots. The UI displays the same
SQL view file embedded into the assembly, not a separately maintained example.

After a confirmed booking, the selected row stays in the current search snapshot
with a disabled **Booked** button. It is not automatically refreshed away.
An explicit new search clears those row markers and reads current availability,
which excludes booked slots. Lost booking races and uncertain write outcomes
never receive a successful Booked marker; writes are not retried.

For repeat takes, the localhost host can opt into `BookingReset__Enabled=true`.
Each confirmed Booked row then offers **Reset booking** until the next search.
Clicking it authorizes deletion of only the returned appointment ID and reopening
of that same provider/slot in one transaction. Other bookings are preserved.
The row returns to **Book slot** only after SQL confirms the reset. A stale
receipt, SQL failure, or uncertain response produces an explicit error and no retry.
Reset is disabled by default; enabling it requires explicit loopback URL bindings.
It uses the configured SQL identity, which needs SELECT/DELETE on the provider's
Appointment table and the existing slot permissions. No new grants are deployed;
the local rehearsal uses the existing authorized development identity. Keep reset
disabled on App Service. A fresh search or reload discards reset receipts; this
is not a bulk reset for older bookings.

Booking uses a fixed provider-to-database allowlist, parameterized slot/key values,
and `UPDATE ... WHERE IsBooked = 0 ... OUTPUT inserted.SlotId`. It checks current
network membership, writes only the owning provider's database, and uses no
explicit transaction or automatic retry. Concurrent attempts cannot both book
the same slot. A lost response is reported as unconfirmed, never success.

## Scene 2 preparation and reset

Use the existing demo skill with the copy-ready
[preparation prompt](prompts/off-camera-prepare-resources.md) or
[Scene 2 reset prompt](prompts/off-camera-reset-scene2.md).
From the repository root, preview off-camera resource preparation:

```powershell
.\startandgrowhyperscale\deploy\00-prepare-part1.ps1 -WhatIf
```

After approval, repeat without `-WhatIf`. Creates missing resource group/Start
logical server only; verifies compatible existing resources without changing them.
No database or firewall rules are created. Scene 2 deployment handles those.
New servers use the signed-in Entra user as administrator.

For a fresh Scene 2 deployment, stop Start app/workload traffic and preview:

```powershell
.\startandgrowhyperscale\deploy\10-reset-part1.ps1 -ExpectedServerName <start-server> -WhatIf
```

After explicit approval, repeat without `-WhatIf` and with `-Confirm:$false`.
This deletes only the Start `caldova-scheduling` database and verifies absence.
All its schema and data are deleted; redeploy in Scene 2, then use the
[off-camera population prompt](prompts/off-camera-populate-database.md).
Both servers, resource group, pool, and all Grow databases remain unchanged.
This is not `06-set-pool-membership.ps1 -Mode Standalone`, which changes provider
compute without deleting databases. Both logical servers and their server-level
cross-database preview settings must always be preserved. Full resource-group
teardown via `99-remove.ps1` is disabled. A newly created server does not inherit
preview enablement; confirm the target if a server appears absent.

These scripts pin every Azure CLI call to the configured subscription and run
synchronously. Environment overrides come from `deploy\00-config.ps1`; reset also
requires the explicit expected server and restricts it to `sql-caldova-start-*`.
Mocked lifecycle tests (no Azure changes), from the repository root:

```powershell
.\startandgrowhyperscale\deploy\tests\part1-lifecycle.tests.ps1
```

## Start-server pool-only rehearsal

The demo skill recognizes **Create the pool on the Start server**. Once all
three Start databases exist, preview only the new pool:

```powershell
.\startandgrowhyperscale\deploy\14-create-part1-pool.ps1 -ExpectedServerName <start-server> -WhatIf
```

After explicit approval, repeat without `-WhatIf`. This creates only an empty
`caldova-network-pool` on Start: Hyperscale Gen5, 8 total vCores, per-database
minimum 0 / maximum 8, no zone redundancy. It retains existing Entra-only,
TLS 1.2, Allow Azure services, local database backups, and server preview settings.
It verifies the current subscription/user without switching accounts and hides
subscription/tenant identifiers in plans and errors.

Compatible existing pools are reused; mismatched pools or failed prerequisite
reads stop without updates or recreation. Creation is independently verified.
No databases are created, moved, populated, or resumed via SQL. Grow resources
and app configuration/connections remain unchanged. Do not run the broader
`04-deploy-sql.ps1` or repoint Grow configuration for this task.
Start pool membership is separately authorized and explicitly targeted:

```powershell
.\startandgrowhyperscale\deploy\06-set-pool-membership.ps1 -Target Start -ExpectedServerName <start-server> -Mode Pooled -WhatIf
```

After approval for Caldova conversion and all three moves, use the same command
without `-WhatIf` and with `-Confirm:$false`. Grow remains the script's default
target; Start never requires repointing Grow or changing the app.

Offline validation:

```powershell
.\startandgrowhyperscale\deploy\tests\part1-pool.tests.ps1
```

## SQL setup

For scripted deployment using the current Azure CLI user's credentials, use
`deploy\07-deploy-scheduling.ps1 -Phase Schema`, then move the databases into
the pool, then `-Phase Network` and `-Phase Verify`. This requires PowerShell's
`SqlServer` module and obtains a fresh SQL access token in memory. The Verify
phase checks the deployment identity, not the app identity.
The Network phase reads the expected app login SID from `sys.server_principals`
in `master`, validates it, and supplies the `AppLoginSid` SQLCMD variable to each
permissions file. Azure SQL does not support `SUSER_SID(login)` in user databases.
Missing login metadata stops setup before the view changes; mismatched existing
users remain explicit failures rather than being silently remapped.
The Entra login SID must be 16 bytes. Azure SQL login-based database users have
an 18-byte SID ending in `AADE`; the permissions guard requires the expected
login SID plus that suffix and an external principal type. A contained user
with only the 16-byte identity SID is not a valid login mapping.
See [Microsoft Entra server principals](https://learn.microsoft.com/azure/azure-sql/database/authentication-azure-ad-logins).
Validate this wiring without Azure or SQL changes with
`deploy\tests\scheduling-network.tests.ps1` (16 mocked checks). Six read-only SQL
fixtures verified valid external-user/group mappings and rejection of contained
users, wrong identities, wrong suffixes, and wrong principal types.
The pool cap policy is defined in `deploy\00-config.ps1`: minimum zero and
maximum `min(pool vCores, 12)`. New pool deployment supplies explicit CLI caps
and verifies them; existing mismatches stop for a separately approved change,
never recreation. Validate creation/reuse safeguards without Azure or SQL with
`deploy\tests\pool-deployment.tests.ps1` (7 mocked checks). On 2026-11-01, the
approved existing-pool update was applied and independently verified: Ready,
24 total vCores, minimum zero and maximum twelve per database. No workload,
booking, schema/permission setup, pool membership, or server changes were performed.
For read-only SQL validation, run `deploy\tests\network-view-read.tests.ps1`.
It executes the canonical JOIN-only SELECT over inline edge-case fixtures and
compares all eight output columns against the previous view semantics using
native live table reads. It verifies colliding IDs, multiple clinics, empty
schedules, membership/booked exclusions, and unchanged past-slot semantics.
It requires the current CLI subscription and all three databases Online in the
existing pool; it does not deploy the view or change users, grants, data, or bookings.
These SQL checks use the deployment identity, not the application's identity.
`deploy\08-configure-app-sql.ps1` configures the app's managed-identity connection
and exact current app-egress firewall rules. The separately requested **Allow
Azure services** setting is enabled in Azure; this script does not remove it.

Run through the MSSQL extension as the Entra administrator, on separate
connections to the specified databases (no `USE` statements):

1. `sql\00-app-login.sql` in `master`: create the app managed identity's server login.
2. `sql\01-scheduling-schema.sql` separately in all three scheduling databases:
   create local appointment tables and seed synthetic future UTC slots; Caldova
   also gets the central provider/clinic directory.
3. Add all three databases to the existing enabled pool using the skill below.
4. `sql\02-network-view.sql` in Caldova: create the native cross-database join view.
5. `sql\03-app-permissions.sql` separately in all three: users **from the login**,
   `SELECT`/`UPDATE` on appointment tables, plus directory/view reads in Caldova.
   Existing mismatched users cause an explicit error; never silently replace them.
   Enable SQLCMD mode and supply `AppLoginSid` from the app login's `sid` in
   `master.sys.server_principals`; the Network deployment phase supplies it
   automatically. Do not substitute a user-database SID or show the value on camera.
6. Verify `sql\04-verify-read.sql` from Caldova using the application identity.
   Then use app steps 3 and 4 to verify actual reads and booking.

Scripts use the current fixed database names. The app identity name
`<network-app>` (`app-caldova-network-<suffix>`) is supplied to `00-app-login.sql`
and `03-app-permissions.sql` as SQLCMD variable `AppName` from `00-config.ps1`,
and to `05-demo-storage.sql` by the app from private configuration.
If porting, coordinate SQL files, the provider
allowlist, source-catalog guard, connection settings, and portal instructions.
Duplicate Entra display names require the documented Object ID login syntax;
use the managed identity's object ID, not a client ID. No SQL login is needed.

The synthetic schema has no triggers or additional audit writes. Do not add a
write to another database to the booking statement/transaction. No app DDL,
`db_owner`, broad server roles, or directory writes are granted.

Seed reruns insert missing dates without deleting data or reopening bookings.
Run setup sequentially; it is not a concurrent migration runner. The initial
Cardiology seed is Caldova +19 days, Ridgeview +2 days; actual search results
depend on today's data and bookings.

Local configuration uses `ConnectionStrings:Scheduling` with
`Authentication=Active Directory Default`. The local developer also needs their
own Entra server login, login-mapped users, and equivalent permissions; the app
identity grants do not grant the developer access. For Azure, `01-deploy-app-service.ps1`
sets a passwordless `ConnectionStrings__Scheduling` override using
`Authentication=Active Directory Managed Identity`. The existing App Service
must have network access to SQL (presenter firewall access does not prove app
access). `/healthz` checks application liveness only, never SQL readiness.

Azure layout for measured mode (all in `caldova-network-rg`, deployed by `04-deploy-sql.ps1`):

- Logical server `<network-server>`, East US 2, **public endpoint + firewall**.
  Microsoft Entra-only authentication is retained for the native cross-database preview.
- `caldova-scheduling` — Hyperscale serverless `HS_S_Gen5_8`, min 1 vCore, auto-pause 60 min.
- `northbrook-scheduling` (provisioned `HS_Gen5_2`), `ridgeview-scheduling` (provisioned
  `HS_Gen5_4`).
- `caldova-network-pool` — Hyperscale elastic pool, 8 vCores, created empty.
- Part 1 server `<start-server>` with its own serverless `caldova-scheduling`
  (deployed by `09-deploy-part1-sql.ps1`; see [Separate Part 1 serverless database](#separate-part-1-serverless-database)).
- Every database and the pool use **Local** backup storage redundancy and **no** zone redundancy,
  so the databases can move into the pool later.
- App will connect passwordless with its system-assigned managed identity, using an
  Entra server login and login-mapped users. No elastic-query SQL login or password
  is needed.

`Demo:Mode` accepts only `Measured`. It does not switch appointments to scripted data. SQL failures are
shown in the app and logged server-side.

## Backlog

Remaining work and presentation options.

| # | Item | Notes |
|---|---|---|
| 1 | **Rehearse Copilot-assisted sizing/deployment** | The Start and Grow skill defines requirements, recommendation, change summary, and approval. Verify supported sizing and exact deployment scope; the current SQL provisioner creates all databases and a pool, not just Caldova. |
| 2 | **Enable auto-pause live in the Azure portal** | Show auto-pause being turned on in the portal instead of setting it at create time. `04-deploy-sql.ps1` currently creates `caldova-scheduling` with `--auto-pause-delay 60`; change it to create with auto-pause off when this lands. Hyperscale auto-pause is preview with a 60-minute minimum delay. |
| 3 | **Live serverless verification** | Measured source path implemented; approve monitoring permissions/load and prove actual rise/fall, sample delay, and agreement with Azure Monitor before publishing/presenting. |
| 4 | **Live native cross-database verification** | **Local search and booking verified (2026-11-01).** The JOIN-only view, provider booking tables, mapped app users, and effective grants are verified. Local app network searches returned ten Cardiology rows (Ridgeview/Caldova) and ten Pediatrics rows (Northbrook/Caldova). An approved Ridgeview slot-8 booking succeeded; SQL confirmed one booked slot/appointment only in Ridgeview and no availability for that slot. A subsequent approved targeted transaction deleted only that rehearsal appointment and reopened slot 8. Follow-up reads confirmed slot 8 remained unbooked, with newer slot-9/10 bookings preserved. The revised UI retains confirmed rows as disabled **Booked** buttons until a fresh search; eight offline checks verify that behavior, provider-scoped markers, repeat-click/in-flight safety, lost races, reset searches, and uncertain outcomes (384 total checks). No additional agent-initiated booking was performed for this UI revision. Deployed managed-identity access remains unverified. The SID guard passed 16 mocked checks and six read-only SQL fixtures. |
| 5 | **Independent Start/Grow chapters** | Part 1 now ends independently; chapter entry/navigation grouping remains to implement, preserving routes and telemetry/SQL disclosures. |
| 6 | **Pool scaling under workload** | Implement an approved capacity change on the existing pool, bounded workload, and measured transition/workload behavior. Connection retry handling is a talking point only; no new retry logic, instrumentation, or tests. Preserve existing booking behavior. |
| 7 | **Measured database growth** | Implemented and offline-tested. Initial live 18/12/15-GiB used-data fill verified; all three allocate 20 GiB. Storage cards measure used/allocated space; opt-in Step 4 grows Caldova to 21 GiB. Crossing 20 GiB under CPU load still needs live rehearsal. No automatic cleanup or data reset. |

## Move into the pool / reset to standalone

Use the workspace skill **start-and-grow-hyperscale-demo** (its "Pool membership"
section) in the same Copilot chat used for the rest of the demo, with prompts such as:

- "Integrate Caldova's acquired providers into the scheduling pool."
- "Return the providers to standalone and restore Caldova serverless."

The skill previews the whole three-database change, obtains approval once, then
runs the canonical script with `-Confirm:$false`.
The same script can be run directly:

```powershell
.\deploy\06-set-pool-membership.ps1 -Mode Pooled -WhatIf
.\deploy\06-set-pool-membership.ps1 -Mode Pooled
.\deploy\06-set-pool-membership.ps1 -Mode Standalone -WhatIf
.\deploy\06-set-pool-membership.ps1 -Mode Standalone
```

Stop appointment/workload traffic first. Changes run synchronously and sequentially;
connections may be interrupted. Every database is checked before the first update,
and every move is verified afterward. A failed operation stops without automatically
undoing earlier moves. It reports partial states; inspect all three databases on
the exact approved server before continuing the desired direction. Do not use
the Grow-only verifier for a Start operation.
`-WhatIf` performs read-only Azure preflight and never updates databases.

Each conversion, detach, or move waits for ARM readiness/configuration instead
of treating a delayed response as failure or repeating writes. The default
`-WaitTimeoutSeconds 1800` / `-PollIntervalSeconds 5` bounds each phase's
read-only observation. Read failures and terminal states stop explicitly.
After interruption, a rerun waits for in-flight operations, skips existing correct
members and completed conversions, and finishes only the remaining approved
changes. User cancellation is not permission to resume automatically. Completion
requires independent verification of all three databases, not just the first move.

Pooled mode converts Caldova to provisioned compute and adds all three databases to
the **existing** Hyperscale pool. Standalone mode restores Caldova to serverless
`HS_S_Gen5_8` (1-8 vCores, 60-minute auto-pause), Northbrook to `HS_Gen5_2`, and
Ridgeview to `HS_Gen5_4`. The empty pool is retained so preview enablement is not
lost. Neither direction deletes data or changes identities, grants, or app state.
Auto-pause is configured, not immediate. Configuration overrides are the same as
the other deployment scripts.

These operations verify Azure placement/compute, not SQL cross-database access.
Native queries require all three databases online in the same pool, an Entra
server login and login-mapped users in every participating database, and object
permissions. Entra-only authentication remains enabled. Native cross-database
queries stop working when the databases return to standalone.

Regression tests (mocked Azure CLI; no live changes):

```powershell
.\deploy\tests\pool-membership.tests.ps1
```

Application query-contract and component-rendering checks (no SQL connections):

```powershell
dotnet run --project .\tests\CaldovaNetworkScheduling.Checks.csproj --configuration Release
```

After approved SQL setup, run the same command with `-- --live` to execute the
real view and race two bookings for one Ridgeview slot. It asserts exactly one
winner and that the slot disappears from availability. **This commits one
synthetic booking and leaves it booked.** It uses `ConnectionStrings__Scheduling`
from the environment and requires the intended test identity's permissions.
Do not run it during pool moves or without approval for the write.

## Playback mode and backup clips

`dotnet run --launch-profile playback` (`http://localhost:5096`) runs the same app with every
Azure and SQL dependency replaced by in-memory stand-ins
([Services/Playback](app/Services/Playback)). Pages, clicks, and on-screen SQL are unchanged:

- **Patient Access:** the measured run, auto-pause (60 s after the run instead of 60 min), and
  resume are driven by a scripted database whose CPU curve follows the 2026-10-25 measured run.
- **Verify / Search & Book:** in-memory slots seeded like `sql\01-scheduling-schema.sql`; the
  view, query, and booking SQL shown are the real ones; a second booking of a taken slot is rejected.
- **Scale & Grow (`/pool`, playback only):** scripted network workload, an online pool scale
  8 → 16 vCores with a brief switch-over, and Northbrook history inserts growing storage
  while compute stays fixed. This beat is not built in live mode.

The playback mode shows no on-screen marker. Disclose in narration that these segments are scripted.

For a repeatable paused-to-resume retake without touching Azure, use:

```powershell
dotnet run --project .\startandgrowhyperscale\app\CaldovaNetworkScheduling.csproj --launch-profile resume-recording
```

This separate local app opens on `http://localhost:5096/` and starts Paused.
The paused opening includes the standard **Clinic day complete. Staff activity
complete.** banner; it clears when sign-in starts.
Its header and five navigation steps match the live app; playback adds no
extra Scale & Grow tab. The legacy playback `/pool` scene remains directly accessible.
Click **Sign in (resume)** to show the approximately 14-second simulated wake-up,
then four simulated workers until you click **Stop**. There is no 30-second
automatic finish. Manual Stop holds the four-staff frame and corresponding CPU reading without
showing staff signing out. Both simulation and live resume use the same
initial 60-second focused chart and manual-stop behavior (ten-minute safety limit);
the separate Run sequence is unchanged.
The normal live/Grow app can remain running on its separate port.
Restart this profile for another paused take; browser refresh alone does not reset
the in-memory database. No Azure operations, SQL connections, billing measurements,
or real booking writes occur. Health reports `playback` / `in-memory` explicitly.

[tools/playback-recorder](tools/playback-recorder) records each sequence to its own native
4K (3840×2160) MP4 at 125% zoom using your installed Edge. Pages are captured at full
resolution (about 9 fps on a typical machine; numbers and charts update at that rate), and the
pointer and click ripples are drawn in at 25 fps from the recorded pointer track:

```powershell
cd app; dotnet run --launch-profile playback          # terminal 1
cd tools\playback-recorder; npm install; node record.mjs   # terminal 2
```

Clips land in `tools\playback-recorder\clips` (gitignored), numbered in play order:

| # | File | Scene |
|---|---|---|
| 01 | `01-p1-run.mp4` | Part 1 scene 3 · measured run |
| 02 | `02-p1-paused.mp4` | Part 1 scene 4 · paused |
| 03 | `03-p1-resume.mp4` | Part 1 scene 5 · sign in (resume) |
| 04 | `04-p2-acquisitions.mp4` | Part 2 take 7 · acquisitions |
| 05 | `05-p2-verify.mp4` | Part 2 take 9 · network check (cross-database reads) |
| 06 | `06-p2-scale.mp4` | Part 2 take 10 · scale the pool under workload |
| 07 | `07-p2-growth.mp4` | Part 2 take 11 · storage growth |
| 08 | `08-p2-search-book.mp4` | Part 2 take 12 · search and book |

Portal and Copilot segments go between them as in the recording script (for example,
the Copilot pool move between 04 and 05). Pass clip names (without the number) to
record a subset; `p2-growth` continues `p2-scale`. Restart the app between full
recordings to reset bookings and pool state.

## Run locally

Public app and launch settings use `{subscription-id}`, not a real Azure
subscription or tenant identifier. Before a live local launch, store the current
subscription privately (PowerShell, from the repository root):

```powershell
dotnet user-secrets set "Azure:SubscriptionId" (az account show --query id --output tsv) --project .\startandgrowhyperscale\app\CaldovaNetworkScheduling.csproj
```

The value is kept outside the repository and loaded for Development launches.
`AZURE_SUBSCRIPTION_ID` is an alternative private environment setting. Resolution
retains each profile's server/database; it does not switch Azure accounts.
Explicit full `ServerlessMonitor:ResourceId` environment/App Service settings
remain supported. Offline replay/playback does not need private identifiers.
Never commit secret-store files, access tokens, or real subscription/tenant IDs.

```powershell
cd app
dotnet run --launch-profile http    # http://localhost:5191, Part 2 server
dotnet run --launch-profile part1   # http://localhost:5099, Part 1 server, measured load enabled
```

Live launches also need the private server names described next.

### Private local configuration

Public files never name the live Azure resources. Docs use `<start-server>`,
`<network-server>`, and `<network-app>` for `sql-caldova-start-<suffix>`,
`sql-caldova-network-<suffix>`, and `app-caldova-network-<suffix>`. The deploy
scripts compute `<suffix>` in `deploy\00-config.ps1` from the current
subscription; `CALDOVA_PART1_SQL_SERVER`, `CALDOVA_NETWORK_SQL_SERVER`, and
`CALDOVA_NETWORK_APP_NAME` override the names. To see the real names, list them
read-only:

```powershell
az sql server list --resource-group caldova-network-rg --query "[?starts_with(name, 'sql-caldova-')].name" --output tsv
```

Tracked `appsettings.json` and `launchSettings.json` use the placeholders
`{network-server}` and `{start-server}` in `ConnectionStrings:Scheduling` and
`ServerlessMonitor:ResourceId`. The app fills them at startup from, in order of
precedence, command line, environment, .NET user-secrets (Development), then the
git-ignored `app\appsettings.Local.json` (never published):

```json
{
  "Azure": {
    "NetworkSqlServer": "sql-caldova-network-<suffix>",
    "StartSqlServer": "sql-caldova-start-<suffix>",
    "AppName": "app-caldova-network-<suffix>"
  }
}
```

`Azure:NetworkSqlServer`/`Azure:StartSqlServer` fall back to
`CALDOVA_NETWORK_SQL_SERVER`/`CALDOVA_PART1_SQL_SERVER`. `Azure:AppName` (or
`CALDOVA_NETWORK_APP_NAME`; `WEBSITE_SITE_NAME` on App Service) is used only by
the storage-seeding grants. In live mode an unresolved or invalid placeholder
stops startup with a message naming the missing setting; it never targets a
default server. Playback and replay substitute harmless offline names and need
no private values. Deployed App Service settings carry complete values.

### Separate Part 1 serverless database

Part 1 needs Caldova serverless and able to auto-pause; Part 2 needs Caldova in the
pool. To keep them from interfering, Part 1 runs against its own logical server,
`sql-caldova-start-<suffix>`, with a database of the same name, `caldova-scheduling`
(serverless 1-8 vCores, 60-minute auto-pause, Entra-only). The `part1` launch profile
overrides `ConnectionStrings__Scheduling` and `ServerlessMonitor__ResourceId`; no code
changes. The Part 1 workload and telemetry use only DMVs, so this database has no
schema. Steps 2-4 of the app are not used with this profile.

```powershell
.\deploy\09-deploy-part1-sql.ps1 -WhatIf                                  # plan only
.\deploy\09-deploy-part1-sql.ps1 -ClientIp <presenter-ip> [-AllowAzureServices]
```

This is the on-camera deployment in Beat 1.2 (the skill runs it after approval).
`-MinVCores`, `-MaxVCores`, and `-AutoPauseDelay` override the config defaults
(1, 8, 60). The script is idempotent and verifies the result. Use
`-AllowAzureServices` when presenting from an
Azure-hosted machine whose outbound IP changes per connection. It sets the
`PresenterClient` firewall rule to `-ClientIp` (or this machine's current IP).

## Deploy to Azure App Service

Requires PowerShell 7, Azure CLI signed in, and the .NET 10 SDK. Subscription comes from
`AZURE_SUBSCRIPTION_ID` or the current `az` account.

```powershell
./deploy/01-deploy-app-service.ps1   # resource group, Windows S1 plan, web app (.NET 10, WebSockets, ARR affinity)
./deploy/02-publish-app.ps1          # dotnet publish + zip deploy
./deploy/03-verify.ps1 -Open         # endpoint checks, then open the app in an Edge app window
./deploy/04-deploy-sql.ps1           # logical server, serverless + provisioned Hyperscale DBs, empty Hyperscale pool
./deploy/05-verify-sql.ps1           # show server, region, databases, and pool state
```

Optional overrides: `CALDOVA_NETWORK_RESOURCE_GROUP`, `CALDOVA_NETWORK_APP_LOCATION`,
`CALDOVA_NETWORK_APP_PLAN`, `CALDOVA_NETWORK_APP_NAME`, `CALDOVA_NETWORK_SQL_SERVER`,
`CALDOVA_NETWORK_SQL_LOCATION`.

Step 1 observation history is held in memory per browser circuit. Pool state lives in Azure; appointments
and bookings live in SQL and survive app restarts. Next/Back navigation does not
mark pool membership as complete.

## Server preservation

Never delete the logical servers or their shared resource group: server-level
cross-database preview enablement must be retained. `deploy\99-remove.ps1`
fails without contacting Azure. For an approved database-only reset, follow
[Scene 2 preparation and reset](#scene-2-preparation-and-reset).
