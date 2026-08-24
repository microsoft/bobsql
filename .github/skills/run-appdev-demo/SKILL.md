---
name: run-appdev-demo
description: >-
  Drive the live three-beat app-dev demo for DATACON 2026, "Why Azure Is the Best
  Cloud for SQL" — Demo 5, the database is the event producer (one INSERT into
  Azure SQL Hyperscale → Change Event Streaming → Event Hubs → two Azure
  Functions racing on separate consumer groups → SignalR → a live browser, with a
  Microsoft Foundry agent triaging the ticket). USE WHEN the presenter says any
  of: "let's run demo 5", "start the app dev demo", "run the ticket stream demo",
  "let's do the change event streaming demo", "walk me through demo 5", "next
  beat", "rehearse demo 5", "pre-flight demo 5", "is demo 5 ready", "reset the
  ticket demo", "fire another ticket", "what do I say when the card appears",
  "the agent verdict is slow, is that normal", or wants step-by-step help
  presenting this arc on stage. Scope is RUN / REHEARSE / RESET the beats ONLY.
  Do NOT use to provision, redeploy or tear down the environment (that's
  build-appdev-demo), to run the Private Link demo 3 beats (that's
  run-privatelink-demo), or to run the Adventure Works SQL MCP or Ward General
  demos — those are separate.
---

# Run the app-dev demo (Demo 5)

Read **`presentations/dataconus2026/whyazurebest/demos/demo5_appdev/README.md`**
first. It holds the architecture, the identity matrix and the reasoning behind
every design choice. Drive from it; do not invent beats.

Kit: `presentations/dataconus2026/whyazurebest/demos/demo5_appdev/`.
This skill assumes the environment already exists and the agent is deployed.

## What the demo proves

A database can be an **event producer**. No trigger, no polling loop, no CDC
reader job, no outbox table, no application code between the commit and the
stream. One `INSERT` commits and Azure SQL itself publishes a CloudEvent.

And nothing is running when it happens. The Hyperscale database is serverless and
may be paused; the function app is scaled to zero. The row typed on stage wakes
the entire chain, it does its work, and it goes back to sleep — with no
credential anywhere in it. Every hop is managed identity.

## Pre-flight — always, before the first beat

```powershell
cd presentations/dataconus2026/whyazurebest/demos/demo5_appdev
az login                 # if the token is stale
.\reset-demo.ps1         # empties the table, reseeds identity, refreshes the firewall
.\05-verify.ps1          # must print 26/26 PASS
.\serve-page.ps1         # opens http://localhost:8080, leave it running
```

Run scripts **synchronously** (`isBackground: false`, `timeout: 0`) and check the
exit code — `05-verify.ps1` exits 1 if anything is out of place.

`reset-demo.ps1` sleeps ~20 seconds on purpose: `DELETE` on a CES-enabled table
emits delete events, and you do not want yesterday's deletes landing on screen
mid-demo. Let it finish.

**26/26 PASS does not prove the agent works.** `05-verify.ps1` has no Foundry
checks at all. Always fire one throwaway ticket during pre-flight and confirm
*both* the card and the verdict strip appear, then `reset-demo.ps1` again.

A new venue means a new egress IP. `Set-PresenterFirewall` handles it, and
`reset-demo.ps1` calls it. If the connection is still refused, suspect **Global
Secure Access** — see the last section of the README; it hooks below the routing
table, so route inspection gives a clean false negative.

## Two things on screen, and the browser is the star

Terminal on one side, browser on the other. The browser must be visible for the
whole demo — the audience needs to see it *empty and connected* before anything
happens, or the payoff reads as a page load.

`serve-page.ps1` runs a tiny local HTTP listener rather than opening the file
directly, because a `file://` page sends `Origin: null` and CORS cannot
allow-list that. If asked why there is a web server at all, that is the answer.

## The three beats

| # | Where | Run | Expected |
| --- | --- | --- | --- |
| 0 | Laptop | `.\serve-page.ps1` | Empty page, badge says **connected**. Nothing has happened yet |
| 1 | Laptop | `.\beat-1-insert.ps1` | `Ticket N committed in X.Xs`. The card appears in the browser, then ~1s later the agent's verdict strip lands on it |
| 2 | Portal | function app → Configuration | No key, no connection string, no SAS token |

Drive **one beat at a time**: say which beat, give the command, wait for the
result, confirm it matches, then ask before moving on.

`beat-1-insert.ps1` takes optional `-CustomerName`, `-Severity` (1–4), `-Subject`
and `-Body`. The defaults are a Sev 1 Contoso Manufacturing outage and they are
tuned to make the agent escalate. Use them for the first firing.

## Narration the presenter should not miss

- **Beat 0** — "connected" is doing work here. The browser has already called
  `/api/negotiate`, and the token it got back was minted by the function app's
  *managed identity*. There is no key in the page. View source if anyone doubts it.

- **Beat 1, the gap is the architecture.** The card appears essentially at commit
  time. The verdict strip lands about a second later. **Do not talk over the
  gap — point at it.** Two functions read the *same* event hub on *different*
  consumer groups and race: `$Default` → `TicketEvent` → `ticketChanged` renders
  the card; `triage` → `TicketTriage` → the Foundry agent → `ticketAction` drops
  the verdict onto that same card. The agent call never blocks the row from
  reaching the screen. That is a deliberate design decision the audience can
  *see*, not a slide claim.

- **Beat 1, how they stitch together.** The two messages arrive independently and
  are matched by `logicalId` —
  `streamid:commitlsn:sequencenumber` from the CloudEvent. That same key also
  dedupes at-least-once redelivery. If the verdict somehow beats the card, the
  page holds it and applies it when the card lands; nothing is dropped.

- **Beat 1, no plumbing.** Say what is *absent*: no trigger, no polling, no CDC
  job, no outbox, no application code between the commit and Event Hubs. The
  database published it.

- **Beat 1, the raw event.** The debug toggle shows the raw CloudEvent JSON. Worth
  one click — it makes "the database emitted a standards-shaped event" concrete,
  and it shows the before/after row image.

- **Beat 2, the payoff.** Open Configuration and read it out. Every setting is
  `__fullyQualifiedNamespace` / `__serviceUri` plus
  `__credential=managedidentity`. There is nothing on that blade to steal, and
  nothing to rotate. `05-verify.ps1` asserts no `SharedAccessKey`, `AccountKey` or
  `AccessKey` pattern exists, so it cannot quietly rot back.

- **If asked about the database's own identity** — the *logical server* has a
  managed identity holding `Azure Event Hubs Data Sender`. The function holds
  `Data Receiver`. And the function has **zero** SQL permissions: no user, no
  schema, no grant. It never connects to the database at all.

## Firing more tickets

`tickets.ps1` defines ten sample tickets. Ticket **10** — *"It is broken" /
"Nothing works. Please fix."* — is deliberately vague. A good agent answers
`info` and asks for repro steps rather than inventing a fix. If the room is
skeptical that the model is really reading the ticket, fire that one:

```powershell
.\beat-1-insert.ps1 -CustomerName 'Northwind' -Severity 4 `
  -Subject 'It is broken' -Body 'Nothing works. Please fix.'
```

Contrast it with the Sev 1 default. Same pipeline, visibly different judgement.

## Between rehearsals

```powershell
.\reset-demo.ps1
```

Empties the table, reseeds the identity to 0 so the next ticket is #1 again,
refreshes the firewall rule, and drains the delete events. CES stays enabled —
this is a rewind, not a rebuild.

## When it does not work on stage

| Symptom | Cause | Move |
| --- | --- | --- |
| Badge never says "connected" | `serve-page.ps1` not running, or CORS | Confirm the page is on `http://localhost:8080`, not `file://` |
| Card never appears, INSERT succeeded | Function cold start | Wait. Flex Consumption cold start is real. Fire a second ticket — it will be fast |
| Card appears, **verdict never does** | `06-agent.ps1` not run, or code deployed before the agent settings | Not fixable on stage. Keep going — the card is the main claim. Fix afterwards with build-appdev-demo |
| Card appears, verdict is slow and erratic | Model changed from `gpt-4.1-mini` | Re-run `bake-off-models.ps1` after the talk |
| INSERT itself hangs ~30s | Serverless database resuming from auto-pause | Expected on a cold first run. This is why pre-flight fires a throwaway ticket |
| Connection refused to SQL | New venue IP, or Global Secure Access | `reset-demo.ps1` re-runs `Set-PresenterFirewall`; if it still fails, pause GSA from the system tray |

The first ticket of the day is always the slowest. **Never let the first ticket
the audience sees be the first ticket of the day.**
