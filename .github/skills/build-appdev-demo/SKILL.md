---
name: build-appdev-demo
description: >-
  Provision, repair, verify or tear down the Azure environment for DATACON 2026
  Demo 5 — "the database is the event producer" (Azure SQL Hyperscale + Change
  Event Streaming → Event Hubs → two Azure Functions → SignalR → browser, with a
  Microsoft Foundry agent triaging each ticket). USE WHEN the presenter says any
  of: "build the app dev demo", "build demo 5", "provision the ticket stream
  demo", "set up the change event streaming demo", "deploy demo 5 on this
  machine", "rebuild demo 5", "the agent verdict never shows up", "05-verify
  passes but the agent does nothing", "redeploy the function app", "re-run the
  model bake-off", "move demo 5 to another region", "tear down demo 5", or moves
  this talk to a new laptop and needs Event Hubs + SignalR + the Entra-only
  Hyperscale server + CES + the function app + the Foundry agent in place. Scope
  is PROVISION + CONFIGURE + VERIFY + TEARDOWN ONLY. Do NOT use to present or
  rehearse the beats (that's run-appdev-demo), to build the Private Link demo 3
  environment (that's build-privatelink-demo), or to build the Adventure Works /
  SQL MCP or Ward General kits — those are separate.
---

# Build the app-dev (Demo 5) environment

Read **`presentations/dataconus2026/whyazurebest/demos/demo5_appdev/README.md`**
first, every time. It is the source of truth for the architecture, the identity
matrix and the CES gotchas. This skill covers only what the README does not: the
order to work in, and the traps that make a *passing* pre-flight lie to you.

All paths are workspace-relative to the **bwsql** root. Kit:
`presentations/dataconus2026/whyazurebest/demos/demo5_appdev/`.

## The shape of it

One `INSERT` wakes a stack that is entirely asleep. The Hyperscale database is
serverless with a 60-minute auto-pause; the Flex Consumption function app is
scaled to zero. Change Event Streaming publishes a CloudEvent over **Kafka on
port 9093**, which is why the Event Hubs namespace must be **Standard** — Basic
has no Kafka surface and the stream group will never connect.

Two functions read the same event hub on **different consumer groups**:
`$Default` → `TicketEvent` → SignalR `ticketChanged` (the card), and `triage` →
`TicketTriage` → Foundry agent → SignalR `ticketAction` (the verdict). They race
on purpose. Everything authenticates with managed identity; there is no key, SAS
token or connection string anywhere in the app settings, and `05-verify.ps1`
asserts that.

## Running the scripts

- **Always synchronous**, `isBackground: false`, `timeout: 0`. Provisioning runs
  minutes; the first connection to a paused serverless database alone takes ~30s.
  Never background them, never poll.
- **Check the exit code.** `05-verify.ps1` exits 1 when anything is out of place.
- Every step is idempotent and individually re-runnable. If step 4 fails, fix it
  and run `.\setup-all.ps1 -From 4`.
- Prefer `execution_subagent` over raw terminal calls for these.

## First build on a new machine

```powershell
cd presentations/dataconus2026/whyazurebest/demos/demo5_appdev
az login
.\setup-all.ps1            # steps 1-5
.\06-agent.ps1             # NOT run by setup-all
.\setup-all.ps1 -From 4    # redeploy so TicketTriage picks up the agent settings
```

Steps 1–5: Event Hubs + SignalR → Entra-only server + Hyperscale DB → schema +
CES → storage + function app + six role assignments + deploy → pre-flight.

Done when `05-verify.ps1` prints **26/26 PASS** *and* a test ticket produces both
the card and the verdict strip. Those are two separate proofs. See below.

## The trap that will cost you a demo

**`setup-all.ps1` stops at step 5 and `05-verify.ps1` never checks the agent.**

- `setup-all.ps1` is declared `[ValidateRange(1,5)]`. There is no `-To 6`.
  `06-agent.ps1` is not in the `$steps` array and never runs from the orchestrator.
- `05-verify.ps1` contains **zero** Foundry assertions — no agent check, no
  `AgentEndpoint` app-setting check, nothing.

So a fresh `setup-all.ps1` yields an environment where pre-flight reports
`26/26 PASS — all checks passed, demo is in its opening state`, the ticket card
renders perfectly on stage, and the agent verdict **never arrives**. Nothing in
the tooling tells you.

If the presenter reports "the card shows up but the agent strip never does",
check these in order before anything else:

```powershell
az functionapp config appsettings list -g bwappdevrg -n bwappdev-func `
  --query "[?name=='AgentEndpoint' || name=='AgentName' || name=='AgentApiVersion']" -o table
```

1. Those three settings missing → `06-agent.ps1` was never run.
2. Settings present but still no verdict → the code was deployed *before* them;
   run `.\setup-all.ps1 -From 4`.
3. Both fine → check the function app holds **`Foundry User`** on `bwappdev-ai`.
   `06-agent.ps1` grants it and prints a `Write-Fail` if it is absent.

## Traps that are already settled — do not rediscover them

| Trap | The rule |
| --- | --- |
| SignalR role | **`SignalR Service Owner`**, not `SignalR App Server`. App Server lets `negotiate` return 200 and the browser show "connected", then 403s every broadcast. Silent, and it looks like a code bug. Both `04-function.ps1` and `05-verify.ps1` carry comments saying so |
| Event Hubs tier | **Standard**, never Basic. CES streams over Kafka `:9093` and Basic does not offer it |
| Event Hubs roles | Data Receiver on the **hub** is not enough — the function also needs **Data Owner on the namespace** to write checkpoints |
| `Body` column type | **`nvarchar(max)`**, never `json`. CES silently skips `json`, `xml`, `vector`, `sql_variant`, `geography`, `geometry`, `image`, `text`/`ntext`, `rowversion`. No error — the column is just absent from the event and the card renders blank. `05-verify.ps1` checks for skipped types |
| Primary key | Must exist **before** CES is enabled. You cannot add or drop one while a table is streaming. `03-schema.ps1` runs the DDL in that order |
| Renaming | The table and its columns cannot be renamed while CES is enabled. Disable the stream group first |
| Existing rows | CES does **not** seed them. The table is created empty on purpose so the first event on stage is the row just typed |
| `TRUNCATE TABLE` | Blocked on a CES-enabled table. `reset-demo.ps1` uses `DELETE` and then waits for the delete events to drain |
| VNet / private endpoint | Not possible. CES streams only to **public** Event Hubs endpoints. Network is demo 3's story; this demo's claim is identity |
| Entra role propagation | `02-sql.ps1` and `04-function.ps1` retry role assignments 6× with 10s waits. A first-run failure here is usually replication lag — re-run the step rather than debugging it |
| CES is preview | Re-run `05-verify.ps1` close to the event. Behaviour and supported types can move |

## Changing the model

`$ChatModel` in `00-config.ps1` is `gpt-4.1-mini` because it won a measured
bake-off (~862 ms median over the ten tickets in `tickets.ps1`), not because it
was picked. The demo's timing depends on it — the verdict strip has to land about
a second behind the card.

```powershell
.\bake-off-models.ps1              # writes bake-off-results.json
.\06-agent.ps1 -Model gpt-5-mini   # one-run override of $ChatModel
```

Do not swap the model without re-running the bake-off and re-reading the medians.

## Renaming or moving to another region

Everything is in `00-config.ps1`, but three values are **globally unique DNS
labels** and can collide: `$ServerName`, `$EventHubNamespace`, `$SignalRName`.
`$StorageAccount` is globally unique too.

`$DestinationLocation` for the stream group is built from the Event Hubs
namespace, so renaming the namespace means `03-schema.ps1` must be re-run — an
existing stream group keeps pointing at the old FQDN and simply stops delivering.
Tear down and rebuild rather than editing a live stream group.

## Teardown

```powershell
.\99-teardown.ps1          # prompts for confirmation
.\99-teardown.ps1 -Force   # skips the prompt
```

Deletes the whole resource group `bwappdevrg` with `--no-wait`. That is safe here
**because this demo owns its resource group outright** — unlike demo 3, which
lives in the shared `bwsqlestaterg`. Nothing else in the talk depends on
`bwappdevrg`.

Teardown is destructive and hard to reverse. **Never run it on the presenter's
behalf without an explicit, unambiguous instruction to tear down.** The
interactive prompt uses `Read-Host`, which returns empty in an agent-driven
terminal — so the unforced path aborts with exit 1 and deletes nothing. Do not
"work around" that by reaching for `-Force`; ask the presenter to run it.

Monitor with `az group show -n bwappdevrg` (it returns an error once gone).

## Prerequisites

| Tool | Evidenced by |
| --- | --- |
| PowerShell 7+ | all `.ps1` |
| Azure CLI, logged in | `Invoke-Az` in `00-config.ps1` |
| .NET SDK 9.0+ | `src/TicketStream.csproj` targets `net9.0` |
| `sqlsim.exe` | `$SqlSim` in `00-config.ps1` → `C:\bwsql\sqlsimtools\sqlsim\build\x64\Release\sqlsim.exe` |
| Edge or Chrome | `serve-page.ps1` probes for both |

There is **no `sqlcmd` and no Functions Core Tools dependency**. T-SQL runs
through `sqlsim` with an Entra access token, and deployment is
`dotnet publish` + `az functionapp deployment source config-zip`. Node is not
required — the page pulls the SignalR client from a CDN.
