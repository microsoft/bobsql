# Demo 5 — The database is the event producer

## What it proves

One `INSERT` into an Azure SQL Hyperscale database lights up a browser on the
other side of Azure, and not one credential exists anywhere in the chain.

Nothing is running when the demo starts. The database is serverless and may be
paused. The function app is scaled to zero. The row typed on stage wakes the
whole stack, it does its work, and it goes back to sleep.

```text
Azure SQL Hyperscale
   │  Change Event Streaming (CloudEvents over Kafka, port 9093)
   ▼
Azure Event Hubs  ticket-events
   ├─ consumer group $Default ─▶ TicketEvent  ─▶ SignalR "ticketChanged"
   │                                             the card appears, immediately
   └─ consumer group triage   ─▶ TicketTriage ─▶ Foundry agent (ticket-triage)
                                                └▶ SignalR "ticketAction"
                                                   the verdict strip, ~1s later
                                                          │
                                                          ▼
                                                       browser
```

Two functions read the **same** stream on **different consumer groups**, racing
each other. That is the design point: the agent call never blocks the card. The
row is on screen before the model has finished reading it, and the verdict lands
on the same card afterwards — stitched by `logicalId`, which is the CloudEvent's
`streamid:commitlsn:sequencenumber`.

`architecture.png` is the slide version of this. `architecture-step1..5.png` are
the same diagram as five reveal layers — paste all five into PowerPoint at the
same position and size, then Appear-on-click to build the flow. Re-render any of
them from `architecture.html` with `_scratch/html2png.mjs` (append `?step=N`).

Every hop is Microsoft Entra managed identity:

| Hop | Identity | Role |
| --- | --- | --- |
| SQL → Event Hubs | logical server system-assigned MI | Azure Event Hubs Data Sender |
| Function → Event Hubs (read) | function app system-assigned MI | Azure Event Hubs Data Receiver |
| Function → Event Hubs (checkpoints) | function app system-assigned MI | Azure Event Hubs Data Owner, namespace scope |
| Function → SignalR | function app system-assigned MI | **SignalR Service Owner** |
| Function → Foundry | function app system-assigned MI | Foundry User |
| Function → Storage | function app system-assigned MI | Blob Data Owner, Queue Data Contributor, Table Data Contributor |
| Presenter → SQL | Entra user | Entra-only admin, no SQL login exists |

**`SignalR App Server` is not enough in Serverless mode.** It is the role you
would reach for, and it fails in the worst possible way: `negotiate` returns 200,
the browser connects, the status badge says "connected", and then every single
broadcast 403s. Nothing appears and nothing looks broken. `05-verify.ps1` asserts
`SignalR Service Owner` specifically.

The function never opens a connection to the database. It needs **zero** SQL
permissions — there is no user, no schema and no grant for it in the database.

## The arc — 3 beats, all live

| Beat | Where | Command | Result |
| --- | --- | --- | --- |
| 0 | Laptop | `.\serve-page.ps1` | Empty page, "connected". Nothing has happened yet |
| 1 | Laptop | `.\beat-1-insert.ps1` | One row. The card appears, then the agent's verdict lands on it |
| 2 | Portal | show app settings | No key, no connection string, no SAS token |

Beat 1 is two things arriving separately. The ticket card shows up the moment
the row commits. Roughly a second later a coloured action strip drops onto that
same card — `ESCALATE`, and a sentence saying what the agent did about it. Let
the gap happen; the gap *is* the architecture. Say it out loud: the card did not
wait for the model.

Beat 2 is the payoff. Open the function app's configuration and there is
nothing to steal: `EventHubConnection__fullyQualifiedNamespace`,
`AzureSignalRConnectionString__serviceUri`, and `__credential=managedidentity`.
`05-verify.ps1` asserts this too, so it cannot quietly rot.

## Why the ticket body is `nvarchar(max)` and not the `json` type

Change Event Streaming **skips** columns of type `json`, `xml`, `vector`,
`sql_variant`, `geography`, `geometry`, `image`, `text`/`ntext`, `rowversion`
and UDTs. It does not raise an error — the column is simply absent from the
event. A `json` payload column would have produced a blank card on stage with
nothing in any log to explain it, and xEvent debugging for CES is not available
on Azure SQL Database.

So the body is `nvarchar(max)`. CES supports LOB columns, truncating each to
1 MB. `05-verify.ps1` checks the table for skipped types on every run.

The JSON story is still on screen: the CloudEvent the database emits *is* JSON,
and the page renders it raw.

## Why there is no VNet or private endpoint

CES can only stream to Azure Event Hubs **public** endpoints — service endpoints
and private endpoints are not supported. A VNet here would have secured nothing,
so it is not in the kit. Private Link is demo 3's story; this demo's security
claim is identity, not network.

## Setup

```powershell
cd presentations\dataconus2026\whyazurebest\demos\demo5_appdev
az login
.\setup-all.ps1        # steps 1-5
.\06-agent.ps1         # the agent -- NOT run by setup-all
.\setup-all.ps1 -From 4
```

Steps, all idempotent and individually re-runnable:

| Script | What it does |
| --- | --- |
| `01-messaging.ps1` | Resource group, Event Hubs namespace (Standard — Kafka needs it), event hub, SignalR in Serverless mode |
| `02-sql.ps1` | Entra-only logical server with a system-assigned identity, Hyperscale serverless DB, Data Sender role, firewall rule for this laptop |
| `03-schema.ps1` | `dbo.SupportTicket`, then enables CES against the event hub |
| `04-function.ps1` | Storage, Flex Consumption function app, six role assignments, the `triage` consumer group, identity-based app settings, CORS, build and deploy |
| `05-verify.ps1` | 26 pre-flight checks |
| `06-agent.ps1` | Foundry project, the `ticket-triage` agent, Foundry User role, agent app settings |

**`setup-all.ps1` stops at step 5. It does not run `06-agent.ps1`.** The
parameter is `[ValidateRange(1,5)]`, so there is no `-To 6` either. On a fresh
build you must run `06-agent.ps1` yourself, and then redeploy the code with
`.\setup-all.ps1 -From 4` so `TicketTriage` starts up holding `AgentEndpoint`,
`AgentName` and `AgentApiVersion`.

Re-deploy just the code with `.\setup-all.ps1 -From 4`.

### Why `gpt-4.1-mini`

It won a measured bake-off, not an argument. `bake-off-models.ps1` runs the ten
tickets in `tickets.ps1` through each candidate and records latency per call;
`bake-off-results.json` holds the raw numbers. `gpt-4.1-mini` came in around a
**862 ms median**, which is what keeps the verdict strip landing about a second
behind the card instead of after the presenter has moved on. Re-run the bake-off
if you change models — the demo's timing is the whole point, so do not swap the
model on vibes.

```powershell
.\bake-off-models.ps1
.\06-agent.ps1 -Model gpt-5-mini    # -Model overrides $ChatModel for one run
```

## Running it

```powershell
.\05-verify.ps1        # must be 26/26
.\serve-page.ps1       # opens http://localhost:8080
.\beat-1-insert.ps1    # the one live command
```

`serve-page.ps1` runs a tiny local HTTP listener because a `file://` page sends
`Origin: null`, which CORS cannot allow-list. Port 8080 is added to the function
app's allowed origins by `04-function.ps1`.

## Between rehearsals

```powershell
.\reset-demo.ps1       # empties the table, reseeds identity, refreshes the firewall rule
```

`TRUNCATE TABLE` is blocked on a CES-enabled table, so the reset uses `DELETE`.
That emits delete events, which is why the script waits for them to drain — you
do not want yesterday's deletes landing on screen mid-demo.

## Teardown

```powershell
.\99-teardown.ps1
```

Deletes the resource group `bwappdevrg` and everything in it. This demo lives in
its own resource group on purpose: demo 3 owns a private DNS zone in
`bwsqlestaterg`, and zone names are unique per resource group.

## Notes and gotchas

- **`05-verify.ps1` does not check the agent at all.** There is no Foundry
  assertion, no `AgentEndpoint` assertion, nothing. It will print
  `26/26 PASS — all checks passed, demo is in its opening state` on an
  environment where `06-agent.ps1` was never run. You get the ticket card and
  never the verdict strip, and pre-flight told you it was fine. Until that gap
  is closed, **prove the agent by firing a ticket**, not by reading the checklist.
- **The database master key needs a password.** It is generated at deploy time,
  used once, and discarded. On Azure SQL the master key is also protected by the
  service master key, so nothing ever supplies it again. It is not a credential
  to any service — but if someone in the audience is counting, that is the one
  password in the build.
- **The primary key must exist before CES is enabled.** You cannot add or drop
  one while a table is streaming. `03-schema.ps1` runs the DDL in that order.
- **CES does not seed existing rows.** The table is created empty on purpose, so
  the first event on stage is guaranteed to be the row you just typed.
- **Renaming the table or its columns will fail** while CES is enabled.
- **CES is in preview.** Re-run `05-verify.ps1` close to the event.
- SignalR is `Free_F1` (20 concurrent connections). Fine for one browser; bump to
  `Standard_S1` in `00-config.ps1` if the audience is going to connect too.

## If the firewall blocks you

`Set-PresenterFirewall` opens the laptop's public egress address, then connects
and asks the server `SELECT client_net_address` to confirm the server agrees.
Normally it does, and that is the end of it.

It will not agree if a tunnelling client is redirecting Azure-bound traffic.
**Global Secure Access** does exactly that, and it is worth knowing how it hides:

- It hooks at the **Windows Filtering Platform** layer, below the routing table.
  `Get-NetAdapter` shows no tunnel and `Find-NetRoute` points at the physical
  Wi-Fi adapter. Route inspection gives a clean false negative.
- Traffic egresses from a Microsoft edge node, so the source address is
  Microsoft-owned and **changes between connections**. Eight distinct addresses
  across `20.x`, `40.x`, and `52.x` were observed from this laptop.
- The portal's **Add client IP** button reports the *browser's* connection — a
  different process over a different path — so it writes a rule `sqlsim` will
  never match.

Measured with GSA stopped, the echo service and the server both reported the same
single address. So the fix is to turn it off, not to chase the pool:

```powershell
Get-Service GlobalSecureAccess*     # Engine / ForwardingProfile / Tunneling
```

If those are `Running`, pause the client from the system tray, then re-run.
