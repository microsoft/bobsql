# Start and Grow Hyperscale: recording script

The exact order of scenes for recording the demo. Beat details, presenter lines,
and evidence rules are in [DEMO-RUNBOOK.md](DEMO-RUNBOOK.md). Status reflects
what has actually been proven as of 2026-10-25.

Copy-ready chat prompts are in [prompts](prompts/): [Scene 2 deployment](prompts/02-deploy-database.md),
[off-camera population](prompts/off-camera-populate-database.md),
[Scene 9 pool move](prompts/09-move-to-pool.md),
[resource preparation](prompts/off-camera-prepare-resources.md),
[Scene 2 reset](prompts/off-camera-reset-scene2.md), and
[provider standalone restore](prompts/off-camera-reset.md).
Paste them into the same on-camera demo chat at the corresponding steps.

| Status | Meaning |
|---|---|
| **Ready** | Run live end to end (deployment, measured run, pause/resume, and billing dry-run on the Part 1 server 2026-10-25) |
| **Rehearse** | Implemented, but not yet run through on camera |
| **Not built** | Do not record; skip or cut |

## Before you record (off camera)

1. Verify the currently signed-in Azure CLI user/subscription without switching.
   Configure the subscription privately as described in [Run locally](README.md#run-locally);
   never show subscription/tenant identifiers in the recording. `<start-server>`,
   `<network-server>`, and `<network-app>` below stand for the
   `sql-caldova-start-<suffix>`, `sql-caldova-network-<suffix>`, and
   `app-caldova-network-<suffix>` names; set the real names in git-ignored
   `app\appsettings.Local.json` as described in
   [Private local configuration](README.md#private-local-configuration).
2. Confirm the starting state. Scene 2 may reuse `caldova-network-rg` and
   `<start-server>` after confirmation and compatibility checks.
   For a fresh deployment, `caldova-scheduling` must not already exist on that
   server. If it exists, the script verifies rather than creates it; obtain
   separate approval for any deletion/recreation. Part 2: all three databases on
   `<network-server>` standalone and Online (Caldova serverless);
   `caldova-network-pool` empty.
   If the resource group or Start server is missing, use the off-camera resource
   preparation prompt and `deploy\00-prepare-part1.ps1` (preview, approve, apply).
   No database is created during this preparation.
3. For Part 1 (after Scene 3), start the app locally with `dotnet run --launch-profile part1`
   (targets the Part 1 server, measured load enabled) and open **one** Edge window
   at `http://localhost:5099/`. (The published App Service has load disabled.)
   Stop any older copy of the app already listening on 5099. Use a real Edge
   window, not the VS Code integrated browser, which suspends the page.
4. Open **one** GitHub Copilot chat. Use that same chat for every Copilot step.
5. Close every other SQL client: VS Code MSSQL connections, SSMS, portal query
   editor. Anything connected keeps the database awake and blocks auto-pause.
6. If the skill's GitHub URL will appear on screen, push branch `bw` first.

## Part 1 - Start with Hyperscale

Allow about **90 minutes** of wall-clock time: the database cannot auto-pause
until it has had no connections for at least 60 minutes (Hyperscale minimum).

| Scene | What to record | Status |
|---|---|---|
| 1 | **Beat 1.1 - Portal choices.** Portal > Create SQL Database. Show Hyperscale, Serverless vs Provisioned, min/max vCores, region, zone redundancy, networking, Entra auth. Do not click Create. | Rehearse |
| 2 | **Beat 1.2 - Copilot sizing and deployment.** Show the skill's Scene 2 workflow. In the new on-camera chat, use the short requirements-led runbook prompt. Use the current Azure user/subscription and existing `caldova-network-rg` / `<start-server>`. Without dialog boxes or estimate questions, Copilot checks compatibility, states pilot assumptions, recommends Hyperscale serverless 1-8 vCores with 60-min auto-pause, and shows the `-WhatIf` plan. Approve the exact plan; deploy `caldova-scheduling` and verify (time-lapse with disclosure). | Script deployment verified 2026-10-25 (7.7 min); revised prompt/reuse conversation needs rehearsal. Existing database verification is not a fresh deployment. |
| 3 | **Portal verification.** Open the exact database from Scene 2. Show server/database names, Hyperscale serverless, 1-8 vCores, and 60-minute auto-pause. Do not change settings or open the query editor. | Rehearse |
| - | **Populate (off camera).** In the same chat: "Populate the database we just deployed with the demo schema and data. This is off camera." Confirm the Scene 2 target, approve the schema/seed preview, verify tables and counts, then disconnect setup clients. Follow the skill's single-database population workflow, not the Grow setup script. | Rehearse |
| 4 | **Beat 1.3 - Capture, then record saved results.** Off camera, approve and capture one complete live **Run** using the [README instructions](README.md#save-a-live-run-then-replay-it-for-recording). Its worker levels rise through 1, 2, 6, 10, hold peak demand for 60 seconds against the eight-vCore cap, then remove two workers every 15 seconds through 8, 6, 4, 2, and 0. Trailing CPU observation brings the plan to 195 s plus startup/in-flight SQL. Restart in `ServerlessRecording:Mode=Replay`, calculating speed from the saved duration for 30 seconds of playback. For the recording, click the unchanged **Run** button: saved staff, patient activity, and CPU advance together, with no speed badge. **Stop** pauses; **Run** continues; **Reset** starts over. | Verify that the actual captured gauge reaches 8 and returns down before using it. Use the actual saved duration, not the plan, to calculate speed. Older captures keep their original ramp; record a new live run to see the revised sign-outs. This is replay of earlier SQL measurements, not a new real-time Azure run. Levels are workers, not guaranteed CPU-used vCores. Capture does not include auto-pause/resume, billing, or Grow. |
| - | **Wait (off camera).** Leave the page open; touch nothing that connects to SQL. About 61 minutes after the run ends, Azure pauses the database. | Ready (paused ~60 min after the run) |
| 5 | **Paused.** The page turns grey: "Paused - no compute charges", readout 0.00, "Clinics are quiet". | Ready |
| - | **Wait at least 10 minutes after the pause** before Scene 6, so the billing chart shows a clear gap. | - |
| 6 | **Resume.** Click **Sign in (resume)**. A staff avatar connects with a spinner; the app retries quietly and shows "First sign-in completed in N s". After successful sign-in, load-enabled demos automatically start four real SQL workers for 30 seconds, then observe CPU for 75 seconds and stop SQL polling. Previous samples and the actual gap are retained; no gap values are fabricated. | Rehearse the new post-resume activity; historical first sign-in resumed in ~15 s. |
| - | **Wait 3-5 minutes (off camera)** for Azure Monitor to publish the new billing minutes. | - |
| 7 | **Billing.** In the portal, go to the Caldova database (`<start-server>` / `caldova-scheduling`) > Metrics > App CPU billed (Sum), 1-minute granularity, from about 10 min before the run to now. Show the bars: rise with the run, step down slowly, sit at the 1-vCore floor, a gap with no bars while paused, bars return after resume. Don't hover over numbers. | Ready (2026-10-25: rise to 4.47 avg billed vCores, step down, 1.0 floor for 60 min, no bars while paused, bars return after resume) |

Post-resume CPU observation includes the preceding 30 seconds of real DMV
samples so the short burst can form a chart line promptly. A fresh page uses
the 135-second baseline/activity/cooldown view, as does sign-in after an earlier
Run. The focused plot excludes the old run so a long pause cannot squash the
resume curve; original samples remain in the raw history with their actual
timestamp gaps. SQL still publishes interval averages
about every 15 seconds, so the chart is not instantaneous. The app checks for
new samples every three seconds to avoid adding a full 15-second polling delay.
The staff display uses actual worker observations at the displayed interval's
midpoint, for both Run and post-resume activity. The header has no elapsed
clock. Do not narrate a delayed interval
as instantaneous CPU, equate workers with cores, or promise an exact CPU
staircase. Cut or time-compress the recording honestly; never replace samples.
Patient rows and counters are captured with each half-second observation while
SQL batches complete, so they come from the same historical frame as the staff
and CPU interval. These workload visuals are not actual appointment writes.
If Stop is clicked early, current staff becomes zero but the last CPU value
and recorded schedule remain; do not narrate that historical CPU as current.
While a run is starting and no samples have arrived, the readout and gauge
show the configured minimum (1.00 in this demo), labeled "minimum vCores".
The first real CPU sample replaces that value, including a real zero. No
minimum placeholder is added to the measured chart or sample table.

The measured app clock, schedule-event timestamps, and sample interval times
show elapsed `HH:mm:ss` since Run, starting at zero. Elapsed time continues
through idle and pause and is preserved on resume in the same page session;
Reset or a new Run starts over. On a fresh page, sign-in starts the elapsed
clock instead. Pre-sign-in baseline samples retain negative elapsed times.
Underlying UTC timestamps and real chart gaps are unchanged. The illustration
keeps its labeled simulated clock.

Serverless CPU-used vCore displays (readout, gauge, chart, and sample-table vCore column)
round upward to quarter-vCore increments, preserving zero, for both Run and
resume. The illustration uses the same formatting. Underlying measurements,
CPU percentage, and configured limits remain unchanged.
This display formatting does not represent allocated or billed
compute, or establish which configuration increments Azure supports.
Provisioned CPU-used vCore displays must instead round upward to whole cores.
The current pool CPU display is a percentage, not a CPU-used vCore readout;
do not apply vCore increments to percentages or change configured capacity.

Say for Scene 7: "When the database pauses, compute billing stops - there are no
bars at all - and it picks back up on the next sign-in." Paused minutes have no
billing value; the chart shows a gap, not a zero.

**End of Part 1.** Optional fallbacks: browse to `/serverless-illustration` for the
labeled 70-second illustration (no SQL), or use the backup clips 01-03.

## Part 2 - Grow without redesigning

**Backup clips:** if live cross-database queries are still unavailable, use the
scripted MP4 clips of each app sequence (see
[Playback mode and backup clips](README.md#playback-mode-and-backup-clips)). They
are the real app in playback mode: same pages, clicks, and on-screen SQL, with
in-memory data and no Azure. Record the Azure portal and Copilot parts live, and
disclose in narration that the app segments are scripted.

Can be recorded in a separate session. Do not run Part 1's measured mode while
the databases are pooled.

| Scene | What to record | Status |
|---|---|---|
| 8 | **Beat 2.1 - Acquisitions.** App Step 2 (`/network`). Show the teal Caldova, blue Northbrook, and coral Ridgeview cards with their starting configurations. The bottom panel sets up the problem: three separate databases, schedules searched separately. This is the acquisition starting point, not live pool verification or the future integrated network. Then switch to the Copilot chat for Scene 9. | Rehearse |
| 9 | **Beat 2.1 - Pool move.** In the same Copilot chat: "Integrate Caldova's acquired providers into the scheduling pool." Copilot shows the preview; confirm no SQL traffic; approve. Caldova leaves serverless; all three move into the pool (several minutes; time-lapse with disclosure). | Rehearse (preflight passed; not yet applied live) |
| 10 | **Beat 2.2 - Network.** In the portal, open `caldova-network-pool`: three databases in the pool. Then app Step 3 (`/verify`): colored provider cards and fictional profiles sit inside one gold outline after all memberships are verified. Each shows actual database state and shared pool capacity. | Resource inspection implemented; does not prove SQL readiness. |
| 11 | **Beat 2.3 - Scale.** App Step 4 (`/scale-presentation`): Run Scheduling & Grow. Show shared pool size and per-database min/max separately from uneven CPU demand, ending at twelve/seven/five in the 24-core model. Caldova's 20-to-30-GiB callout ends the scene. Scale Pool to 8/24 during activity illustrates sharing without restarting. | Growth-event ending previously rehearsed; revised limits/uneven-demand verification is tracked below. Real `/scale` proof remains separate. |
| 12 | **Beat 2.5 - Search and book.** App Step 5 (`/appointments`): Cardiology local, then **Search the entire network**; show the provider-keyed LEFT JOIN view (no union) before the booking INSERT; book a Ridgeview slot and leave the row visible as **Booked**; Pediatrics shows Northbrook. The view panel precedes the booking SQL panel. For a repeat take, the opted-in localhost host offers **Reset booking** beside that Booked row before a new search. | SQL setup, local network searches, and one real slot-8 booking verified. SQL confirmed only Ridgeview changed. Slot 8 was then reset with explicit approval; no other booking was reset. Persistent Booked-row and exact-receipt reset behavior have offline checks; the new reset button has not been exercised against live SQL. A fresh search still excludes booked slots. Deployed managed identity remains unverified. |

**Scene 11 presentation choice:** Use `/scale-presentation` with
`PoolPresentation__Enabled=true` for the recording animation. It stops as soon
as the 20-to-30-GiB allocation callout appears, normally around sixteen seconds,
within the thirty-second maximum. CPU demand varies independently, ending at
twelve/seven/five in the 24-core model; the completed cards retain those readings.
Cards show shared capacity and minimum zero / maximum twelve separately from
CPU-used values. Scaling the model to eight sets maximum eight and shares the total. Caldova's
in-memory allocation expands from twenty to thirty with the large callout.
No on-screen speed-up caption appears. Run again resets only the presentation
model; there are no SQL writes, bookings, or Azure operations. The narration
must not claim these are live SQL samples.

**New pool cap policy:** Future real deployments/scales use minimum zero and
maximum twelve per database in the 24-core pool, maximum eight in the eight-core
pool. Existing live limits require separate approval before correction; the
current 24-core pool was updated with approval and verified on 2026-11-01 as
Ready, 24 total vCores, minimum zero and maximum twelve. The illustration models
the new cap policy but is not proof that live Azure limits have changed.

With recording enabled, use the app's Network/Scale navigation to retain the
same recording capacity and limits across both pages. Demo screens omit playback,
illustration, and fictional-data notices. Network has no live-inspection link;
use `/verify-live` directly for independent real Azure inspection. Modeled
readings remain distinct from live evidence despite this cosmetic change.
Do not reload mid-take: a full reload starts a fresh recording circuit.
Offline checks and repeated normal Edge navigation verified 8 -> 24 -> 8.

Current local rehearsal verified 24 distinct CPU frames, initial two/two/two,
final twelve/seven/five, immediate completion on allocation expansion, and
minimum/maximum display changes during activity. The real ARM-backed Network
cards show shared 24 and minimum zero / maximum twelve. Prior rehearsal verified both scale controls during
activity, repeat/reset, Stop, reduced motion, and expanded layouts without
scrolling at 1366x768, 1024x768, and 900x700. No SQL data was changed.

**Off-camera real proof:** Preview and explicitly approve
`deploy\13-rehearse-pool-growth.ps1 -ExpectedServerName <network-server> -IncludeGrowth`.
It records real UTC CPU samples, query successes, and used/allocated growth;
it rejects incomplete growth rather than giving a successful verification.

**Real-page alternative:** Beat 2.4 uses real storage within Scene 11. Seed Caldova/Northbrook/Ridgeview
off camera to 18/12/15 GiB used through the Grow Storage phase. Enable local
`PoolGrowth__Enabled=true`; **Run Scheduling & Grow** inserts only synthetic
Caldova data past 20 GiB, capped at 21 GiB, while showing measured used/allocated
space on every card. Growth finishes on SQL-confirmed used and allocated space
above 20 GiB. Verify crossing 20 GiB live. Stop retains committed data; the next Run
does not reset it. No fictional storage numbers or automatic data cleanup.
Cards are moderately larger with measured CPU values and storage bars; no CPU
chart appears underneath them. The measured allocation increase gets a large
**20 → 30 GiB** callout and brief Caldova card highlight; the actual before/after
values remain visible after Stop. Once growth is already confirmed, the button
reads **Run Scheduling**; another allocation-change take requires an approved reset.
For another take, stop the app and preview `deploy\12-reset-demo-storage.ps1`
with `-ExpectedServerName <network-server> -WhatIf`. After approval,
the synthetic-data-only reset restores 18 GiB used / 20 GiB allocated without
recreating the database or changing scheduling data. The actual reset took
about 4m12s; reopen the app and verify **Run Scheduling & Grow** before recording.
Existing 0–8 per-database limits stay unchanged, so a 24-vCore pool does not
give any single database 24 vCores. Scheduling uses bounded read-only worker
ramps and real DMV samples, not fixed eight-core usage or appointment writes.
The gradual ramps start two workers per database and add groups of two,
peaking at nine after twenty seconds to target eight CPU-used cores.
Worker counts are not cores; this does not automatically scale provisioned compute.
Only six workers start immediately; the first
SQL sampling interval includes the rising load. Do not smooth or invent values,
and rehearse this revised measured curve before claiming its shape or peak.
100,000-iteration scalar batches target near 24 used cores without the previous
million-loop batch duration. Fifteen-second holds and three-worker ramp-down steps give three 45-second profiles
with a 15-second cooldown: a 60-second plan, excluding startup and overrunning
SQL. Real growth has a 45-second budget; expiry stops inserts normally and
refreshes actual sizes rather than showing a red limit-reached alert. A neutral
status reports unconfirmed allocation growth, never a false success.
Final verification can add up to ten seconds; genuine SQL failures remain visible.
An explicitly approved off-camera
pre-fill to 19.75 GiB used is recommended for recording, but has not been
performed; initial seeding remains 18/12/15.
This can briefly bring all
three databases near eight cores. Show the measured header total, not a claimed
guaranteed peak. The revised workload needs a live rehearsal.

The pool-membership script verifies all three databases before rendering its
final summary directly to the host. It displays the pool name rather than a
subscription-bearing resource ID; formatting records are not returned to callers.
Network resource fields show "Loading..." during management reads and only show
"Not verified" when those reads fail. After a local app restart for code updates,
reload the browser to establish a new Blazor connection before rehearsing.
Matching oval outlines highlight the shared-vCore readout on each pooled card;
these repeat one pool's capacity, not three independent allocations.
Network cards are compact by default: provider name, database, shared compute,
and database state stay visible, along with the fictional patient/staff profile.
There is no Details disclosure or technical query section. No SQL check, open-slot counts,
or SQL access field appears on Network. Measured growth stays on Scale,
separate from live CPU evidence.
Acquisitions provider profiles use fictional planning figures, not live patient,
staff, or department metrics: Caldova 24,000 patients / 180 staff / 5 departments;
Northbrook 6,000 / 45 / 3; Ridgeview 12,000 / 90 / 3. The fictional patient and
staff totals follow the 8:2:4 compute proportions for visual storytelling only,
not a validated database-sizing formula. Care capabilities match the demo
scheduling specialties.

**End of Part 2.**

## Reset (off camera)

### Scene 2 - fresh deployment

Use [the Scene 2 reset prompt](prompts/off-camera-reset-scene2.md) in the same chat.
Preview with `deploy\10-reset-part1.ps1 -ExpectedServerName <start-server> -WhatIf`,
then approve the exact database deletion before applying without `-WhatIf`
and with `-Confirm:$false`. Stop dependent Start traffic first.
Only the Start `caldova-scheduling` database is deleted. Keep the resource group,
both servers, all Grow databases, and the pool unchanged. Redeploy during
Scene 2, then recreate schema/data with the off-camera population prompt.
This operation does not restore provider compute or reset Grow bookings.

### Optional provider standalone restore - no deletion

In the same Copilot chat: "Return the providers to standalone and restore
Caldova serverless." Caldova returns to serverless 1-8 vCores with 60-minute
auto-pause; Northbrook 2 vCores; Ridgeview 4 vCores. Data, bookings, and the
pool are kept. Booked slots are not reopened.

## Open items before a full recording

1. Push branch `bw`; decide whether to publish this app version to App Service
   (load generation there stays off until access is restricted and the app
   identity's SQL permissions are verified).
2. Rehearse Scenes 2-11, keeping one on-camera Copilot chat for deployment,
   pool integration, and reset. Scene 1 remains in the recording but is skipped
   during this rehearsal.
3. Verify current cross-database app behavior on `<network-server>` /
   `caldova-network-pool`, including the view, permissions, and app identity
   (Scenes 10 and 11). Schema is already in all three databases.
4. Rehearse Beat 2.3 (implemented pool scaling under workload) and Beat 2.4
   (implemented measured growth), after verifying initial storage seeding.
5. Update the runbook beats for the single Patient Access page and the resume step.
