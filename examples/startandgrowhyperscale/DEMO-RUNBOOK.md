# Caldova - Start and Grow Hyperscale

Two independently presentable chapters tell the story. Use the
[Start and Grow skill](https://github.com/microsoft/sqlhyperscalemechanics/blob/main/.github/skills/start-and-grow-hyperscale-demo/SKILL.md)
for real deployment, verification, and operations. Recording-specific skill
instructions are maintained privately outside the repository. For the take-by-take
recording order and current status, see [RECORDING-SCRIPT.md](RECORDING-SCRIPT.md). Stop between beats and at
the chapter boundary. "Next" is not approval to change Azure.

The current app still has four numbered pages. The chapter split below is the
agreed presentation flow, not a claim that new app navigation or scaling
controls have already been implemented.

## Readiness gates

| Capability | Current source baseline / required proof |
|---|---|
| Copilot sizing/deployment | Skill interviews, recommends serverless Hyperscale 1-8 vCores, and deploys the Part 1 server/database with `deploy\09-deploy-part1-sql.ps1` (`-WhatIf` plan, then apply). Script plan verified 2026-10-24; not yet run on camera. |
| Independent chapter navigation | Not yet implemented; existing routes are mapped below. |
| Serverless Patient Access | Published illustration passed the Edge 1 -> 4 -> 1 -> pause -> resume cycle. Current app uses SQL DMV CPU samples and a staged 0 -> 8 -> 0 worker ramp; published 2026-10-23 with load generation disabled. Harness ramp measured 0 -> 6.94 -> 0 vCores with no failures (6-7 accepted); app-page ramp not yet run live. Actual billing/pause/resume history is captured; portal rehearsal and deployed SQL identity verification remain. SQL load generation is disabled. |
| Pool membership | Canonical script/skill implemented; verify current live state before each run. |
| Pool scale under workload | Local 24/8 controls and bounded three-clinic workload/CPU telemetry implemented and offline-tested. Faster differing worker ramps target near 24 used cores; the actual peak and scale-under-load behavior still require live rehearsal. Retry handling is a talking point only. |
| Database growth | Real measurements and bounded inserts are implemented and offline-tested. Initial live fill verified at 18/12/15 GiB used, each with 20 GiB allocated. Step 4 grows Caldova to 21 GiB; crossing 20 GiB under CPU load still needs live rehearsal. |
| Native cross-database search/booking | Source implemented; live deployment/app-identity verification remains unproven by this document. |

Measured historical evidence is in [README.md](README.md). It is not
current Azure state. Stop a live beat if its gate has not passed; do not present
planned capabilities as working.

## Preparation

- **One GitHub Copilot chat session for the whole demo.** Every on-camera Copilot
  step (Beat 1.2 sizing/deployment, Beat 2.1 pool integration, and the reset)
  runs in that same chat, driven by the single
  [start-and-grow-hyperscale-demo skill](https://github.com/microsoft/sqlhyperscalemechanics/blob/main/.github/skills/start-and-grow-hyperscale-demo/SKILL.md).
  The presenting machine must be signed in with `az login` to the demo subscription.
- Start with the three databases standalone for the serverless chapter.
- Run the scheduling SQL setup in [README.md](README.md#sql-setup) before presenting.
  The native view requires all three databases in the enabled pool during setup.
  After setup, they can be returned to standalone; the view cannot be queried
  across databases again until pooled placement is restored.
- Publish the updated app only after checking it locally.
- Current source uses SQL DMV CPU data and opt-in real SQL load; billing remains
  a separate Azure Monitor portal visual. SQL observation prevents auto-pause:
  stop observation and all SQL clients before the pause beat. The DMV revision
  was published 2026-10-23; the existing illustration remains unchanged.
  Search and booking execute SQL over synthetic schedules, with no scripted fallback.
- Use the app's managed identity for the deployed read/write verification.
- `<start-server>`, `<network-server>`, and `<network-app>` stand for the
  `sql-caldova-start-<suffix>`, `sql-caldova-network-<suffix>`, and
  `app-caldova-network-<suffix>` resources in `caldova-network-rg`. Real names
  stay in git-ignored `app\appsettings.Local.json`; see
  [Private local configuration](README.md#private-local-configuration).

## Part 1 - Start with Hyperscale

### Beat 1.1 - Azure Portal choices

**Say:** "Normally I need to choose the database configuration here. If I don't
know what I need to deploy, that's OK."

**Do:** Open the Azure SQL database creation experience without submitting it.
Show the actual choices: service tier, compute model/range, region,
availability/redundancy, and connectivity. Verify the current portal labels
during rehearsal; do not leave "XYZ" in the on-camera script.

**Prove:** Distinguish choices the customer must make from what the platform
manages. This beat creates nothing.

### Beat 1.2 - Copilot-assisted sizing and deployment

**Say:** "That's a lot of choices. Instead, I'll switch to VS Code. GitHub Copilot
uses our deployment skill to ask about my requirements, recommend a
configuration, and deploy it with scripts and the Azure CLI."

**Do:** Show the workspace
[skill](https://github.com/microsoft/sqlhyperscalemechanics/blob/main/.github/skills/start-and-grow-hyperscale-demo/SKILL.md).
Use this prompt:

> Help me deploy a database for Caldova Patient Access. Usage peaks in the
> morning, with nights and weekends idle. We need automatic compute scaling,
> low idle cost, and room to grow without sizing storage. A short wake-up
> delay is fine. Use the currently logged-in Azure user and subscription,
> resource group `caldova-network-rg`, and the existing Start server
> (`sql-caldova-start-*`) in it.
> Recommend a configuration, state assumptions, and show the plan for approval
> before deploying.

This is Scene 2. Show the skill's "Scene 2 - Requirements-led deployment"
section so the audience can connect the short prompt to its workflow. Hyperscale
serverless is the recommendation, not an instruction in the prompt.
Copilot uses the current Azure CLI user/subscription and checks the named
resources for existence and compatibility. No questionnaires or numerical
estimates are required: show missing details as pilot assumptions in the plan
and wait for approval. Do not silently switch subscriptions or recreate servers.
If the database already exists, verification is not a fresh deployment;
deletion/recreation requires separate approval.

The supplied requirements and proposed pilot assumptions are:

| Topic | Requirement to say |
|---|---|
| Workload | Clinic staff sign in to schedule and check in patients. Busy weekday mornings, light in the afternoon. |
| Peak | We don't know the exact peak yet. It should scale up on its own for the morning rush; we don't want to pay for peak all day. |
| Idle | Nights and weekends nobody uses it. |
| Warm-up | A short wait for the first sign-in after a quiet period is fine. |
| Data | Starts small, grows as we add clinics. I don't want to size storage. |
| Region | East US 2. |
| Availability | Pilot: no zone redundancy, local backup redundancy. |
| Security | Microsoft Entra only; no SQL passwords. |
| Budget | Lowest possible cost when idle. |

Copilot's recommendation, and why:

| Choice | Value | Reason |
|---|---|---|
| Service tier | Hyperscale | Storage grows automatically; no size to pick. Can join a Hyperscale elastic pool later. |
| Compute | Serverless, `HS_S_Gen5_8` | Intermittent use; billed per second for what is used. |
| vCore range | 1-8 | Max 8 is headroom for an unknown morning peak. Min 1 is the lowest minimum Azure allows with a max of 8 (verified with the regional capability API), so idle-but-online cost is as low as possible. |
| Auto-pause | 60 minutes | Nights and weekends. 60 minutes is the Hyperscale minimum; Hyperscale auto-pause is preview. |
| Redundancy | Local backups, no zone redundancy | Pilot requirement; also matches the pool Caldova joins in Part 2. |
| Auth | Entra-only | Requirement. |

Copilot then shows the change summary by running:

```powershell
.\startandgrowhyperscale\deploy\09-deploy-part1-sql.ps1 -WhatIf
```

For this demo include `-AllowAzureServices` in both preview and apply, without
`-ClientIp`; no presenter-IP lookup or rule is needed. Retain the setting if
already enabled and leave existing rules untouched.
After you approve, it runs the same command without `-WhatIf`. It reuses
the confirmed resource group/server and creates `caldova-scheduling`, then
verifies the result. Creating a missing server requires explicit approval;
the resource group must already exist for this script.
Creation takes a few minutes; time-lapse with disclosure.

For off-camera preparation of missing resources, use the
[preparation prompt](prompts/off-camera-prepare-resources.md) and
`deploy\00-prepare-part1.ps1` (preview, approval, then apply). This creates the
resource group and Start server only. For a fresh Scene 2 deployment, use the
[database-only reset prompt](prompts/off-camera-reset-scene2.md) and
`deploy\10-reset-part1.ps1 -ExpectedServerName <start-server> -WhatIf`.
Deletion requires separate approval before applying without `-WhatIf` and with
`-Confirm:$false`. No Grow databases, servers, pool, or resource group are deleted.

**Prove:** The verified result matches the approved plan (`HS_S_Gen5_8`, min 1,
auto-pause 60). Do not claim the 1-8 range came from measurement; it is a
starting point that Beat 1.3 then observes. Verify that the intended GitHub
branch contains the skill before showing its repository URL on camera.

### Scene 3 - Verify the deployed database in Azure Portal

**Say:** "Here is the database Copilot deployed from those requirements."

**Do:** Open the exact server/database verified in Scene 2. Show its name,
Hyperscale service tier, serverless compute, 1-8 vCore range, and 60-minute
auto-pause configuration. Do not change settings or open the SQL query editor.

**Prove:** Portal configuration agrees with the approved deployment plan.
Continue to Patient Access only after this check.

**Off camera, before Scene 4:** In the same deployment chat, prompt:

> Populate the database we just deployed with the demo schema and data.
> This is off camera.

Follow the skill's "Off-camera - Populate the deployed database" workflow:
confirm the exact Scene 2 target, preview and approve the single-database
schema/seed operation, then verify tables and counts. Use the existing
`sql\01-scheduling-schema.sql` only on that database, not the multi-provider
deployment script. Disconnect afterward. This setup can resume compute and
restart the idle period; it does not prepare or move the Grow databases.

### Beat 1.3 - Caldova Patient Access (current app Step 1, `/`)

For the recording, first capture one complete approved live Run, then restart
with `ServerlessRecording:Mode=Replay` and speed calculated from the saved duration
for a 30-second presentation. Keep the **Run** label;
the page has no playback/speed badge. See the README's
[capture/replay instructions](README.md#save-a-live-run-then-replay-it-for-recording).
The shared clock compresses saved CPU and patient/staff frames together.
Do not describe this replay as a fresh real-time Azure run. Capture does not
include auto-pause, resume, billing, or Grow; keep those operations separate.

**Presenter decision (2026-10-22): two complementary visuals.**
The app now uses a **195-second planned sequence**:
one worker starts as soon as the database connection is ready, without
an idle baseline. The levels are 1, 2, 6, and 10 workers at 0, 15, 30, and
45 seconds. Hold the peak for 60 seconds, then remove two workers every
15 seconds: 8, 6, 4, 2, and 0 workers at 105 through 165 seconds.
Ramp-up lasts 45 seconds; sign-outs span 60 seconds,
followed by 30 seconds of trailing CPU observation. **Stop** cancels the workload
and SQL observation immediately instead of waiting through cooldown; it keeps
existing samples and returns the controls to idle.
Workload duration is 165 seconds; startup/connection and in-flight batches
can add to elapsed time. SQL telemetry can arrive after this short cooldown;
do not infer a final zero or a measured peak from the plan. Staff avatars,
schedule activity, and phase status use the actual worker observation at the
displayed 15-second CPU interval's midpoint, rather than the current stage.
Patient activity and counters are recorded alongside the half-second worker
observations as SQL batches complete, then the matching full frame is shown.
They are workload visuals, not actual booking writes. After Stop, the CPU
readout and schedule are explicitly historical; zero current staff does not
mean the last recorded CPU value was zero.
The presentation omits the CPU interval/staff explanation line; raw samples
remain available behind the chart. Keep the sign-out phase until measured CPU
reaches zero before saying everyone has signed out. During live capture,
Stop remains current. Both live and replay omit the header elapsed clock;
internal elapsed tracking and raw sample times remain available. Replay
starts at zero while CPU is pending, without adding a chart point.
A transition can straddle a CPU interval. The 1/2/6/10 sequence
is worker load against an eight-vCore database cap, not CPU-used vCores.
Post-resume activity retains its separate 75-second observation.
The recording capture must be verified to reach the gauge's **8-vCore** peak
and return down; a 6-7-vCore peak does not satisfy this recording target.
Do not alter measurements to force the peak. Current source measures
approximately 15-second `sys.dm_db_resource_stats` interval averages using
`avg_cpu_percent * cpu_limit / 100`, not Azure Monitor CPU data.
The approved harness ramp from an Azure client (2026-10-23 00:45-00:54 UTC)
rose smoothly to a **6.94-vCore** peak and back to 0 with no failures. The
app-page ramp has not been run against SQL. The DMV/ramp revision was
published 2026-10-23 with load generation still disabled. The approved
fallback at `/serverless-illustration` explicitly illustrates 1 -> 4 -> 1 ->
paused -> resumed. Its complete cycle has been verified in standalone Edge.
Never describe that curve as actual SQL telemetry.
Use the published scene at
`https://<network-app>.azurewebsites.net/serverless-illustration`.
The measured page and illustration are separate routes of the same app;
only one presentation window is needed.

In the portal, billed compute is the story. Do not spend the presentation
comparing CPU with memory or hovering over billing numbers. Keep the chart
accurately labeled and let the bars show:

1. Quiet but online: average billed compute near the configured **1-vCore minimum**.
2. Activity: billed compute rises above that minimum.
3. Activity stops: billed compute falls back toward the minimum.
4. Confirmed auto-pause: **no compute charge** during the paused interval.
5. An approved application connection resumes the database: billed compute returns.

**Gate:** Verify the complete real billing/pause/resume timeline before presenting.
Earlier tests prove billed rise/fall. Historical Activity Log and billing now
also confirm auto-pause at **2026-10-21 20:54:22 UTC** and resume at
**2026-10-22 16:01:41 UTC**, with absent billing samples during the confirmed
paused interval and samples returning afterward. These are separate historical
views, not a newly recorded single synchronized app-and-portal session.
Approve monitoring permissions and real compute usage, restrict app access, and
enable load only for an approved run. The 0 -> 8 -> 0 ramp is measured in the
harness only; the published app contains it but load generation is disabled. The labeled
illustration is verified.
No workload-memory savings claim is needed.

**Chart units:** `app_cpu_billed` supports **Sum**, in vCore-seconds. To show
average billed vCores, divide each bucket's Sum by its duration in seconds
(60 for a one-minute bucket), using an Azure Monitor workbook transformation
and bar visualization. Alternatively, use the raw Metrics bar chart with its
actual units: **60 vCore-seconds per full minute corresponds to 1 average vCore**.
Do not relabel raw Sum as vCores or select an unsupported Average aggregation.

For auto-pause, stop all SQL workloads and close connections, including query
editors, SQL health checks, and other clients. Allow the configured 60-minute
idle delay plus the actual transition time; do not promise an exact pause time.
Observe status/activity through ARM/portal, not SQL probes. Record the confirmed
Paused interval and the later resume event. A missing metric bar alone is not
proof of pause or zero charge; label the confirmed paused/no-compute-charge
interval without fabricating zero-valued metric samples. Record/time-lapse if
needed and retain real timestamps. Resuming requires explicit approval for
the connection/compute use, not a fabricated animation.

After the DMV revision is separately approved, published, and verified with the
application identity, click **Observe SQL CPU**. Capture quiet SQL intervals.
Start the approved bounded workload, then stop it and continue observing.
Chart real, approximately 15-second interval averages with UTC end timestamps.
Stop **observation** before the auto-pause beat. There is no scripted patient activity,
pause/resume, or guaranteed duration/curve. Record and time-lapse if necessary;
label the recording and preserve real timestamps.

In the Azure portal, open the Caldova database for the separate billed-compute
bar chart. In **Monitoring > Metrics**, select `app_cpu_billed`, **Sum**, with
the intended historical or newly recorded range. For one-minute buckets,
vCore-seconds / 60 gives average billed vCores in a workbook. Show bars without
hovering; do not use Azure Monitor CPU values to drive or validate the app chart.

The app shows raw SQL CPU percentages and each sample's own vCore limit beside
the converted CPU-used values. Portal billing is a different metric and interval.
These are consumption/billing, not allocated-core measurements. Missing samples
alone do not prove zero charges.

Explain per-second CPU/memory-based compute billing with the configured minimum:
idle but online still incurs compute charges; paused compute costs nothing.
Storage and applicable backup charges continue while paused. If already pooled,
restore standalone compute only with approval; the measured serverless app
rejects pooled/provisioned targets instead of plotting misleading data.

Explain that demand returning may require compute and caches to warm back up.
The chart does not directly measure cache reclamation, resume duration, or
retry behavior. Retry handling remains a talking point, not a new implementation.

**End Part 1 here.** Stop SQL work and observation. Start Part 2 only when Bob
requests it; the serverless page no longer automatically advances to acquisitions.

### Explicit illustration fallback

If live timing is unsuitable, stop the measured workload/observation and choose
**Scripted illustration (fallback)**, or navigate to `/serverless-illustration`.
Do not silently switch on telemetry failure. The page labels staff, activities,
cores, clock, and pause/resume as scripted. It runs no SQL and supplies no billing
evidence. Say: "This illustrates the behavior; now let's look at actual usage
and billing from a recorded workload."

The real portal billing chart is mandatory even with this fallback. Use a disclosed
historical window; it need not match the scripted scene. An initial usable window
is **2026-10-22 16:35-16:43 UTC** on the actual Caldova database. Use one-minute
App CPU billed **Sum**, converted to average billed vCores in a workbook or shown
with explicit raw units. CPU/memory comparison is optional diagnostic detail,
not a presentation requirement. This earlier window shows rise/fall only; capture
a longer confirmed pause/resume view as documented below. The
[README live result](README.md#live-result---2026-10-22) records observed values.
Confirm chart rendering/time range during rehearsal; API samples alone do not
prove the portal/workbook presentation has been rehearsed.

**Historical pause/resume view:** set the portal to **2026-10-21 19:45 UTC through
2026-10-22 16:45 UTC** (October 21 14:45 through October 22 11:45 CDT), using
15-minute App CPU billed Sum bars. Quiet full buckets before pause are around
900 vCore-seconds (1 average billed vCore). The last pre-pause bucket is partial;
the confirmed paused interval has no samples. Billing returns after resume;
zoom to **16:35-16:43 UTC on October 22** for the stronger rise/fall view.
No hover narration or on-stage calculation is required. No portal screenshot
or saved workbook is claimed verified merely from these API results.

## Part 2 - Grow without redesigning

Preflight this chapter independently: confirm all three database configurations,
the existing preview-enabled pool, SQL setup, and app identity. Use the
standalone baseline for the full migration story. If already pooled, disclose
that state; restoration needs its own approval. Before presenting the full
chapter, the scaling/workload gate above must pass.

### Beat 2.1 - Bring the acquired providers together (current app Step 2, `/network`)

Show Caldova, Northbrook Family Clinics, and Ridgeview Specialty Care. The cards
describe their starting configurations, not live Azure state.

Switch to the same GitHub Copilot chat used for Beat 1.2 and type:

> Integrate Caldova's acquired providers into the scheduling pool.

The start-and-grow skill's pool membership procedure previews the exact subscription/resources
and requests approval. Ensure no scheduling/workload traffic is active before
approving. It adds databases to the existing preview-enabled pool, not a new one.
Caldova converts from serverless to provisioned compute. Wait for all three
postconditions to pass.

### Beat 2.2 - One pool, one network (current app Step 3 Network, `/verify`)

In the Azure portal, open the pool directly:

1. Resource group `caldova-network-rg`.
2. Server `<network-server>`.
3. Hyperscale pool `caldova-network-pool`.
4. Confirm all three scheduling databases are pooled and online.
5. Inspect actual pool capacity; no app-generated metrics are shown.

The Network app page shows verified membership and shared capacity without a
SQL access check. Search & Book demonstrates native cross-database reads and
booking separately on Step 5. Step 4, Scale (`/scale`), offers **Scale Pool to 24** and **Scale Pool
to 8**: each click authorizes the real server-side CLI update without another
confirmation. Both buttons disable while scaling, and verified capacity refreshes
automatically. Scaling keeps minimum zero and sets maximum per database to
12 at 24 pool vCores, or 8 at 8 pool vCores. Include both capacity and cap in the
approved operation; verify both. Eight is not an inherent per-database limit.
Live controls are localhost-only, opt-in, and disabled on public deployments.

When the local recording opt-in is enabled, Network (`/verify`) instead shares
the Scale illustration's selected capacity and per-database limits across
in-app navigation, without on-screen playback/illustration notices or a
live-inspection link. Use `/verify-live` directly for real Azure inspection.
Keep narration and evidence accurate: modeled readings are not live telemetry.
Neither recording page changes Azure. A full browser
reload creates a fresh recording circuit; with recording disabled, Network
retains its real ARM inspection behavior.

Present the scaling and database-growth beats before moving to Search & Book.

### Beat 2.3 - Scale the pool while watching workload

**Gate:** Local scale controls and bounded three-database scheduling/CPU observation
are implemented and offline-tested. Rehearse actual scale-under-load behavior
before presenting it live. Run Scheduling drives bounded worker ramps on
each clinic and displays measured CPU, not equal allocations. Stronger batches
and two immediate workers per clinic ramp in groups of two to nine workers within twenty seconds to target
near 24 used cores. This requires all three databases to approach eight cores;
do not promise different usage at every instant. The low start makes room for a
more gradual measured rise; keep the actual 15-second averages without invented
intermediate values. Nine workers target eight CPU-used cores; counts are not
cores and do not change provisioned capacity. Each profile holds fifteen
seconds, stops three workers per five-second step, and ends at forty-five,
followed by fifteen seconds of observation. Rehearse the revised curve before
claiming its shape or peak. Moderately larger cards show
latest measured CPU values and simple used/allocated storage bars, without
CPU charts. Storage growth is measured from SQL data files. Retry handling is a talking
point only; do not build retry logic, instrumentation, or tests for this demo.

**Say:** "The service prepares the new compute and switches over when it's ready.
This is an online operation, but the application can see a brief interruption
at the end, so it needs connection retry handling."

**Do:** Record the existing capacity and approved target on the same pool.
Start the bounded workload and capture a baseline. Apply the approved scale
operation while keeping workload active. Observe operation state alongside
timestamped successful requests, latency, SQL/connection errors, and observed
workload recovery. Continue observation after ARM completion. Explain the need
for connection retry handling without claiming the app demonstrates it.

**Prove:** Actual before/after capacity and application behavior over the same
timeline. ARM success alone does not prove application recovery. Report any
observed interruption duration; if none is observed, say that rather than
claim "zero interruption." A retry demonstration is not required. Preserve
existing booking behavior; never blindly retry a booking whose write outcome
is unknown.

### Beat 2.4 - Show the database growing in the workload flow

**Gate:** Complete approved initial Grow storage seeding with
`deploy\07-deploy-scheduling.ps1 -Phase Storage`: Caldova 18, Northbrook 12,
Ridgeview 15 GiB used. Enable `PoolGrowth__Enabled=true` only on the localhost
demo after verifying SQL access. Offline checks pass; rehearse actual inserts
and timing before presenting the growth beat live.

**Say:** "We don't size database storage by choosing a core count. Hyperscale
handles storage growth separately; there's no storage tier to resize here."

**Do:** On Scale, click **Run Scheduling & Grow**. It authorizes bounded synthetic
inserts on the real `/scale` page only. For the explicitly chosen bounded
recording illustration, use `/scale-presentation` with the local presentation
opt-in; its Scale and Run controls change only the in-memory model. There is
no on-screen speed-up caption. Do not describe its values as live SQL telemetry.
The illustration stops as soon as the prominent 20-to-30-GiB allocation
callout appears, normally around sixteen seconds, within the thirty-second
maximum. Scale controls work during activity without restarting the clock;
the 24-vCore model uses per-database minimum zero and maximum twelve, displayed
separately from CPU-used values. Demand starts at two each, then varies by
provider and finishes at twelve/seven/five. The eight-core model caps each
database at eight and shares the eight-core total. Final CPU and expanded-storage readings remain
visible; another Run resets only the in-memory baseline.
Keep real proof separate in `deploy\13-rehearse-pool-growth.ps1 -IncludeGrowth`,
preview and approve that operation, and verify its actual UTC samples and
20-to-30-GiB allocation change. It never books, resets, or changes compute.

**Real verification:** **Run Scheduling & Grow** authorizes bounded synthetic
inserts into Caldova only, capped at 21 GiB used, while scheduling runs across all
three databases. Growth finishes once SQL confirms used and allocated space
above 20 GiB. Show Caldova crossing 20 GiB and actual file allocation
increasing; a prominent before/after allocation callout and brief Caldova card
highlight appear only when actual allocation increases during the run.
Northbrook/Ridgeview retain their staggered seeded sizes. Stop
cancels and joins activity and refreshes space measurements.

**Prove:** Scaling compute does not require a matching manual database-storage
resize. Do not imply unlimited I/O, that all I/O limits are independent of
compute. Used and allocated sizes are distinct GiB measurements, excluding logs.
Committed data remains on Stop; another Run does not reset it or exceed the
21-GiB ceiling. Already-grown storage changes the button to **Run Scheduling**
and is preserved; another allocation-change take requires an approved off-camera
reset. Grouped scheduling lasts up to 45 seconds with 15 seconds of
observation: a 60-second plan, excluding startup and overrunning SQL.
The Grow-only off-camera reset is `deploy\12-reset-demo-storage.ps1` with an
explicit expected network-server name. Preview with `-WhatIf`, approve its
dummy-table truncation/shrink/refill scope, and stop app/workload traffic before
applying. Actual 18-GiB used / 20-GiB allocated restoration is verified; it took
about 4m12s because the current shared payload baseline is rebuilt.
Growth is also capped at 45 seconds; its throughput is not guaranteed.
Reaching that budget stops inserts normally and refreshes actual storage;
there is no red limit-reached alert. A neutral status reports growth past
20 GiB that has not been confirmed. Verification can add up to ten
seconds; genuine SQL or verification failures remain explicit.
An explicitly approved off-camera pre-fill to 19.75 GiB used is recommended
for the recording but has not been performed. Do not call the
beat complete until the actual increase is seen.

### Beat 2.5 - Search the network, book at the provider (current app Step 5, `/appointments`)

1. Search Cardiology with **Search the entire network** unchecked.
2. Check the box and search again. Compare the returned lead time to Caldova only.
   Dates/counts are actual seeded SQL results, not fixed claims.
3. Expand **Behind the view**. Caldova's central provider/clinic directory joins
   to local and native three-part-name remote appointment tables using three
   provider-keyed `LEFT JOIN`s, without a union. Clinic and slot IDs are local
   to each provider; the provider-key guards keep schedules from multiplying
   or mixing. `COALESCE` selects the matching schedule's fields.
4. Book a Ridgeview slot. The displayed SQL runs one transaction from the Caldova
   connection: it updates the slot and inserts an appointment row, both in
   `[ridgeview-scheduling]`, a cross-database `INSERT` with one write database.
5. The selected row stays visible with a disabled **Booked** button. A fresh
   search excludes it from open availability. A second session holding the old
   result can demonstrate that only the first booking succeeds; a lost race
   must not display a successful Booked marker.
   For another take on the opted-in localhost host, click **Reset booking**
   beside that Booked row before starting a new search. This deletes only that
   exact rehearsal appointment and reopens its slot; the button returns to
   **Book slot** after SQL confirms it. No bulk reset or automatic write retry.
6. Switch to Pediatrics to show Northbrook's schedule.

All displayed times are UTC. Booking records availability only; there is no
patient information in this synthetic scenario.

The transaction writes only to the provider's database (the preview allows one
write database per transaction). A competing booking returns unavailable, not
success. A lost write response is an unknown outcome: inspect that provider's slot
in SQL before retrying. No automatic write retry and no write to Caldova.

## Reset and chapter exit

End Part 2 after search/booking; do not automatically change Azure state.
If pool compute was scaled, restoring its previous capacity is a separate
approved operation. The membership reset below does not restore pool capacity.

Stop dependent SQL traffic. In the same Copilot chat, type:

> Return the providers to standalone and restore Caldova serverless.

The skill restores Caldova's 1-8 vCore serverless compute with 60-minute
auto-pause, Northbrook's 2 vCores, and Ridgeview's 4 vCores. It retains all data,
bookings, schema, grants, and the preview-enabled pool. Auto-pause is not immediate.
Native cross-database reads/writes will no longer work while standalone.

Stop observation before any compute reset. Starting a new observation clears
its local chart only; it does not reset Azure. There is no scripted
pool reset/integration button. Seed reruns do not reopen booked slots; they add
missing synthetic dates only.
