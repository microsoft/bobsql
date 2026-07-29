# Ward General — Demo Run-of-Show

Click-by-click script for the **hyperscale-developer** talk. Demos are
Hyperscale-only and **pre-deployed** — nothing is provisioned on stage.

Status legend: ✅ written · 🚧 to draft · 🎥 recording fallback needed

---

## Pre-flight (before you walk on)

| # | Check | How |
|---|---|---|
| 1 | `az login` valid | `az account show` (passwordless auth for app + DAB) |
| 2 | **This client's IP allowed** on `collierhealth-17` | `./build/preflight-firewall.ps1` — detects your public IP and **prompts** before adding one named firewall rule (never opens `0.0.0.0`). `run.ps1` calls it automatically; `-Yes` = no prompt, `-SkipFirewall` on `run.ps1` bypasses it. **A new venue/hotel IP is the #1 "can't connect on stage" cause.** ⚠️ **Rotating egress (corpnet/NAT):** if the server rejects with **40615** despite a `/32` rule, your outbound IP rotates across a range (the IP `ipify` sees ≠ the IP SQL sees). Authorize the whole range: `./build/preflight-firewall.ps1 -Cidr 131.107.0.0/16 -Yes`. |
| 3 | App **and** DAB running | `./build/run.ps1` → starts **both**: DAB on http://localhost:5000 (REST/GraphQL/MCP) *and* the app on https://localhost:7170. Wait for `DAB is up on :5000` then the browser opens. (`shutdown.ps1` stops both; `-NoDab` for app-only.) |
| 4 | MCP server started in VS Code | open [.vscode/mcp.json](../../.vscode/mcp.json) → **Start** on `wardgeneral-dab` (shows "12 tools") |
| 5 | Copilot in **Agent** mode | trigger one tool call so the **Allow** dialog is pre-dismissed |
| 6 | RLS default | app board shows **All providers · Admin** (everyone) |
| 7 | **Schema Designer + Copilot dry-run** (Demo 1 beat) | On the venue network, open the **MSSQL extension → Schema Designer** for `wardgeneral`, click the **Copilot icon**, and confirm it responds; then ask **"what is `ChartRepository`?"** and confirm a good answer. This beat is **live only** — prove the icon + Copilot work here before you walk on. |

> ⚠️ **No recording fallbacks exist (as of 2026-07-28).** Every beat below is
> **LIVE ONLY** — there is no 🎥 backup to cut to if the venue network or a login
> fails. Pre-flight (esp. #2 firewall + #3 app/DAB) is your only safety net;
> run it early. If recordings get made later, replace this note and re-flag the
> per-demo "live only" callouts.

---

## Demo 1: 🏗️ Build it — show the app on Hyperscale ✅

**Pre-built:** the app, DAB, and the database are **already deployed and running**
before you walk on (see Pre-flight). Nothing is built or provisioned on stage —
Demo 1 simply *shows* the running app and makes the point that it's an ordinary
.NET app on an extraordinary database.

**One line:** *"An ordinary Blazor app, ordinary ADO.NET, ordinary stored
procedures — and the database underneath is Azure SQL Hyperscale. Nothing in the
code knows or cares."*

**Why it matters (the through-line):** the app never speaks SQL text — every read
and write is a `clinical.*` stored procedure through the DAL
(`ChartRepository` → `WardGeneralConnectionFactory`). That single design choice is
what lets the *same* procedures later serve DAB and an AI agent unchanged.

### Live steps (browser → https://localhost:7170)

| # | Do | The point |
|---|---|---|
| 1 | Open the **census board** — units, beds, active encounters | The worklist is one proc: `SearchEncounters`. |
| 2 | Click a bed → **patient chart** | The whole chart (demographics, vitals, notes, labs, meds, allergies) is `GetPatientChart` — one call. |
| 3 | **Show the GitHub repo + structure** — `presentations/hyperscale-developer/build/` (app `src/`, `dab/`, `sql/`) | It's an ordinary repo: a Blazor app + DAL, a DAB config, and a folder of plain `.sql`. Nothing Hyperscale-specific in the code. |
| 4 | **MSSQL extension → Schema Designer, then the Copilot icon** — connect to `wardgeneral`, open the **Schema Designer** (visualize + design the schema), then click the **Copilot icon** in the designer and let it **describe what it sees** | Copilot reads the live schema and calls out the good stuff on its own — **native `json` columns** (`InsuranceJson`, `IntakeJson`, `ResultJson`, `FindingsJson`), the **`vector`** embedding table, and the **AI-assistance / ledger** tables. "It's an ordinary SQL Server database — and look what the engine already does." Previews the natural-language theme that pays off in 🤖 Modernize. |
| 5 | **Ask Copilot: "what is `ChartRepository`?"** (and let it tie schema → app code) | The answer is the whole thesis in one shot: the DAL calls **only** `clinical.*` stored procedures (no ORM, no ad-hoc SQL), and those *same* procs become DAB's REST/GraphQL/MCP tools and the AI agent's tools, unchanged. Optionally open **`04-procedures.sql`** to show `GetPatientChart`/`SearchEncounters` behind it. |
| 6 | **Explore the Azure portal** — `wardgeneral` on `collierhealth-17` → Overview | It's **Hyperscale** (HS_Gen5_8): compute + storage + replicas — "the app you just saw runs on *this*." |
| 7 | On the portal, **call out Zone Redundancy = On** and **1 HA replica** | **Create-time choices** — both were decided at deploy and are **immutable** (no `az sql db update` for zone redundancy; you'd rebuild the DB to change it). Sets up "Make it HA." |

**⚠️ Live only — no recording fallback.** The app tour, the repo/schema walk, and
the portal look are all live; if the venue network / login is shaky, lean on
pre-flight rather than a cut-to-video (none exists).

**Close:** *"Same SQL Server engine, same T-SQL, no app rewrite to adopt
Hyperscale — you point the connection string and go."*

## Demo 2: 🔒 Secure it ✅

**One line:** *"The app didn't change — the database decides who can sign in and who
sees which rows. The app just says *who's asking*; the engine does the filtering."*

### Live steps

| # | Do | The point |
|---|---|---|
| 1 | In the app, change **"Viewing as"** from *Admin — all patients* to a **single attending** | The board + chart **instantly narrow** to that provider's patients — **Row-Level Security in the engine**, not a `WHERE` clause in the app. |
| 2 | Flip back to **Admin** | All patients return — same query, same DAL, different `SESSION_CONTEXT`. |
| 3 | Show the DAL **connection** — [WardGeneralConnectionFactory.cs](build/src/WardGeneral.Data/WardGeneralConnectionFactory.cs#L48) `Create()` | `Authentication = ActiveDirectoryDefault` · `Encrypt = Mandatory` · **no password, no key**. Say it precisely: *"Passwordless, Entra-only. **Locally it's my `az login`; in Azure it's the app's managed identity** — same code, the only difference is who hands us the token."* `ActiveDirectoryDefault` is a **credential chain**, not a fixed identity: on the laptop there's no MI so it uses your developer Entra login; deployed to App Service / Container Apps it picks up the managed identity. |
| 4 | Show the DAL **RLS stamp** — [ChartRepository.cs](build/src/WardGeneral.Data/ChartRepository.cs#L261) `OpenWithContextAsync()` | On every open, `sp_set_session_context` writes **ProviderId + Role (read-only)** from the "Viewing as" selector; the RLS predicate on `clinical.Encounter` reads it and filters. Pool reuse re-stamps — no reconnect. |
| 5 | Show the **RLS T-SQL** — [10-row-level-security.sql](build/sql/10-row-level-security.sql) `security.fn_encounterAccess` + `security.EncounterAccessPolicy` | The **other end of the loop**: the `FILTER PREDICATE` reads `SESSION_CONTEXT('ProviderId'/'Role')` — NULL or `Admin` ⇒ all rows, else only that attending's encounters. The app stamps it, the engine enforces it. |

### Exact code to show (file · lines · what to point at)

1. **Passwordless connection** — [WardGeneralConnectionFactory.cs](build/src/WardGeneral.Data/WardGeneralConnectionFactory.cs#L48-L71) **lines 48–71**
   → point at **L54** `Encrypt = Mandatory`, **L58** `Authentication = SqlAuthenticationMethod.ActiveDirectoryDefault` (no UID/PWD), **L64–L67** `RetryLogicProvider` (retry ties to "Make it HA").
2. **DAL stamps `SESSION_CONTEXT`** — [ChartRepository.cs](build/src/WardGeneral.Data/ChartRepository.cs#L261-L279) **lines 261–279**
   → point at **L270–L278** the two `sp_set_session_context` calls writing `ProviderId` + `Role` with `@ro = true` (read-only).
3. **RLS predicate function** — [10-row-level-security.sql](build/sql/10-row-level-security.sql#L48-L63) **lines 48–63**
   → point at **L59–L64** the three `SESSION_CONTEXT(...)` branches: NULL/NULL ⇒ system session (all rows), `Role = 'Admin'` ⇒ whole unit, else `ProviderId = AttendingProviderId`.
4. **Security policy** — [10-row-level-security.sql](build/sql/10-row-level-security.sql#L71-L76) **lines 71–76**
   → `ADD FILTER PREDICATE` (hides reads) + `ADD BLOCK PREDICATE … AFTER INSERT` (can't write as someone else) `WITH (STATE = ON)`.

> Presentation tip: show them **in this order** — connection (who you are) → DAL
> stamp (who you're acting as) → predicate + policy (what the engine enforces).
> It's the same `SESSION_CONTEXT` value flowing app → engine.

**Slide-only (named, not demoed):**
- **TDE — versionless customer-managed key** (BYOK, auto-rotate; `kv-collierhealth-tde`).
- **Private Link** — `pe-collierhealth-sql`, private endpoint in the VNet; public path can be denied for private-only.
- **Microsoft Defender for SQL** — threat protection / vulnerability assessment.

> **Append-only ledger** is a *"Secure it"* point but we **show it later**, in the
> **AI-in-the-engine** demo — the tamper-evident audit is on `AIAssistanceLog`, so it
> lands better once the AI assistance has actually written a row.

**Close:** *"No secret in the app, and no row-filtering logic in the app either —
the connection proves *who you are* with a managed identity, the DAL tells the engine
*who you're acting as*, and Row-Level Security does the rest. Same code, the database
enforces it."*

## Beat: ⚡ Scale it ✅

**One line:** *"Compute you dial, storage that grows itself, read scale-out on
demand — the app keeps one connection string."*

> Vector search (the Research page) is **reserved for Modernize it** — don't open
> it here. Scale it stays on the portal knobs + the `sqlsim` surge.

### Live steps (portal + sqlsim)

| # | Do | The point |
|---|---|---|
| 1 | 🌊 **Kick the surge** — `./Run-ReadSurge.ps1 -DurationSeconds 60 -Report` (from `utilities/sqlsim/read-surge/`) | Read-only load through the app's real procs (`ops.vBedCensus`, `GetPatientChart`, `SearchEncounters`) hits the **primary** compute. ~3,300 reads / 10s on 8 vCores. |
| 2 | Show the **querystats HTML report** that auto-opens | Per-query **server CPU** + logical reads + throughput — *"here's the compute this load burned."* |
| 3 | Portal → **compute slider** (2 → 192 vCores) | **Online rescale**, constant time regardless of data size; a brief reconnect at cutover is **hidden by the app's retry logic** (→ Make it HA). Pull it, kick it, move on — don't wait the single-digit minutes. |
| 4 | Portal → **no storage slider** | Storage **grows automatically** to 128 TB, billed on actual allocation — nothing to pre-provision or manage. *"Compute you dial; storage just grows."* |
| 5 | Portal → **named replica** options | Read scale-out is a knob (dedicated read endpoint, serverless, own SLO). *Tease:* *"there's a read-only replica serving research in complete isolation — we open it in **Modernize it**."* |

### Generating the surge + report

```powershell
# from presentations/hyperscale-developer/utilities/sqlsim/read-surge/
./Run-ReadSurge.ps1 -DurationSeconds 10 -Report   # surge + auto-opened HTML report
```

- **Read-only, safe on the live DB** — every batch is a SELECT or read proc; no writes.
- **Loads the primary on purpose** (no `ApplicationIntent=ReadOnly`) so scaling vCores is the answer.
- **Before/after scale:** run `-Report`, scale, run `-Report` again, compare the two HTML files (throughput up, CPU-per-query down).
- Prereqs + preview caveat: [utilities/README.md](utilities/README.md). `sqlsim` is a **preview** — not for production testing.

**Slide-only:** elastic pools (many hospitals sharing a compute pool) as Collier
Health grows.

**Close:** *"A compute slider, storage that grows itself, and read scale-out on
demand — and the app keeps one connection string. Try that on a tier without named
replicas: you'd be building and syncing a second database."*

## Beat: ♻️ Make it HA — slide-only ✅

**One line:** *"High availability and disaster recovery you configure, not build —
and the app's single connection string never changes."*

> **No live demo.** Slide + the HA focus diagram
> ([wardgeneral-architecture-ha.svg](architecture/wardgeneral-architecture-ha.svg)).
> The app-side HA story (`RetryPolicy`) was already shown in Secure / Scale.

### Slide bullets

- 🛟 **Built-in HA replicas** — hot-standby replicas (0–4), automatic failover, no WSFC / AG to build.
- 🌍 **Zone redundancy** — replicas across availability zones for a higher SLA.
- 🔁 **Geo-replication / failover groups** — cross-region DR; the app's single endpoint stays put through failover.
- 💾 **Automated backups** — snapshot-based, fast regardless of database size.
- ⏪ **Fast point-in-time restore** — any second in the retention window, from snapshots.

**Why Hyperscale matters here:** on a build-it-yourself tier you'd stand up and
patch a Windows failover cluster / Availability Group and babysit backup jobs. Here
HA replicas, geo failover groups, snapshot backups, and fast PITR are platform
features — the app's only HA code is the `RetryPolicy` you already saw.

**Close:** *"You don't build HA on Hyperscale — you turn it on. Zone-redundant
replicas, cross-region failover, and point-in-time restore, with no cluster to own."*

## Beat: 🤖 Modernize it ✅

**One line:** *"The same relational chart — now with document, text-mining, vector,
and agent superpowers built into the engine. No new service to run."*

> 🕒 **START THIS FIRST — it runs for several minutes.** Before movement 1, kick off
> the **AI-assistance chat**: select provider **Claudia Ward**, prompt **"which
> patients should I prioritize?"**. It fans out gpt-5 over her patients, so it's
> slow — **launch it, then talk through JSON/RegEx and Vector Search while it cooks**,
> and circle back to the result when you reach movement 3 (Clinical Assistance).
> ⚠️ Live only / gpt-5 + Foundry dependent — smoke-test off-stage before the session.

Four movements, climbing from T-SQL to an AI agent — all against one Hyperscale DB.

### 1 · JSON and RegEx

| # | Do | The point |
|---|---|---|
| 1 | Show the native **`json`** columns — `Patient.InsuranceJson`, `Encounter.IntakeJson`, `LabResult.ResultJson` (JSON index on `IntakeJson`) — [02-tables.sql](build/sql/02-tables.sql) | Documents live *in* the row — typed, queryable, indexed; not a blob. |
| 2 | Show the **`REGEXP_*` T-SQL** — `clinical.vChartNoteSignals` in [03-views.sql](build/sql/03-views.sql#L236-L271): `REGEXP_SUBSTR` pulls BP / HR / temp / SpO2 / pain / follow-up out of free-text notes into a json object | Text-mining **in the engine** (RE2), deterministic — no app-side parsing. |
| 3 | Show the **chart card** that renders it — note-signals card, [Chart.razor](build/src/WardGeneral.Web/Components/Pages/Chart.razor#L209) | Same `NoteText` the AI layer embeds, mined live. |

### 2 · Vector Search  *(pays off the Scale tease)*

| # | Do | The point |
|---|---|---|
| 1 | In the app open **Research** → semantic search over the 60k notes — [Research.razor](build/src/WardGeneral.Web/Components/Pages/Research.razor) | Vector search in the app, running on the **serverless named replica** — the isolated read endpoint from Scale. |
| 2 | Show the **embedding T-SQL** — [06-ai-embeddings.sql](build/sql/06-ai-embeddings.sql): `CREATE EXTERNAL MODEL`, `ClinicalNoteEmbeddings VECTOR(3072, float16)`, `AI_GENERATE_EMBEDDINGS`, `CREATE VECTOR INDEX … diskann` | Model, vector type, embeddings, and the DiskANN index — all T-SQL. |
| 3 | Show the **search proc** — `clinical.SearchSimilarNotes` in [08-research-vector-search.sql](build/sql/08-research-vector-search.sql): `AI_GENERATE_EMBEDDINGS(@q) … VECTOR_SEARCH … SELECT TOP (N) WITH APPROXIMATE` | It **embeds *and* searches on the replica** — no separate vector store, no load on the primary. |

> **Demo prompt** (rich, diverse cross-condition results): **"Short of breath with leg swelling and fatigue; history of high blood pressure and diabetes."**
> Backups: *"Fever, cough, and chest pain with confusion."* · *"New confusion and weakness in an older adult."* (widest spread).
> Symptom-only phrasing crosses multiple condition clusters (heart failure + hypertension + diabetes), so it returns richer, more varied matches than a hyper-specific query.

### 3 · Clinical Assistance

| # | Do | The point |
|---|---|---|
| 1 | Show the **assistance proc** — `clinical.GenerateClinicalAssistance` in [07-ai-assistance.sql](build/sql/07-ai-assistance.sql): embeds a case summary → `VECTOR_SEARCH` for context → calls **gpt-5 via `sp_invoke_external_rest_endpoint`** → logs to `AIAssistanceLog` | **RAG inside the database**: retrieve with vectors, reason with gpt-5 — all T-SQL. |
| 2 | *(Optional live)* click the **bedside AI-assistance card** that calls it | Grounded summary + suggested triage, citing its notes — human-in-the-loop. |

### 4 · Chat for assistance  *(finale — the same procs as an agent)*

| # | Do | The point |
|---|---|---|
| 1 | Show the **MAF agent code** — [WardGeneralAgent.cs](build/src/WardGeneral.Agent/WardGeneralAgent.cs): a Microsoft Agent Framework agent whose tools are the DAB **MCP** server; passes `ActingProviderId` on every call | The in-app assistant. **RLS carries into AI** — the agent only ever sees the acting clinician's patients. |
| 2 | Show **`dab-config.json`** — the same 11 `clinical.*` procs exposed as REST / GraphQL / **MCP**, no API code — [dab-config.json](build/dab/dab-config.json) | One config turns stored procs into agent tools. *(Native `json`/`vector` go through thin `…Api` adapters — the engine is a release ahead of the tooling.)* |
| 3 | **Quick test in VS Code** — Copilot (Agent mode) over the MCP server: *"find notes similar to 'elderly chest pain with elevated troponin'"* → `search_similar_notes`; then *"AI clinical assistance for encounter 249"* → `clinical_assistance` (~10–15s, the finale) | English → the **identical** procs. Copilot shows the tool, args, approval, JSON — proof it hit Hyperscale, not a hallucination. |

### Stage safety — writes are locked (read-only agent)
The 8 write procs (admit, discharge, vitals, meds, labs, notes, diagnosis,
allergy) are **hidden from MCP** (`custom-tool: false`) **and** require the
`authenticated` role — so the anonymous demo returns **403** on every surface.
The agent can read, search, and run AI, but **cannot mutate** patient data on
stage. To re-enable a write demo, flip those entities back to `anonymous` +
`custom-tool: true` in [dab-config.json](build/dab/dab-config.json) and restart DAB.

**Close (the thesis):** *"App (ADO.NET), REST/GraphQL, and this agent all call the
identical `clinical.*` procedures — one contract, three consumers. The database
isn't behind the AI platform; it **is** the AI platform."*

**Why Hyperscale matters here:** the 60k-note vector index, the read-scale research
replica, and the in-engine gpt-5 calls all run against one Hyperscale database —
no separate vector store to provision, sync, or secure.

### Gotchas rehearsed
- **`clinical_assistance` is the slow one** (gpt-5) — lead with `search_similar_notes` for the snappy AI moment; finish with assistance.
- **Say "using wardgeneral"** in the first prompt so the agent picks the right tool group.
- **Native `json`/`vector` are unsupported by DAB** — the chart/admit/lab procs go through thin `…Api` adapters (`build/sql/11-dab-adapters.sql`) that serialize json↔text at the boundary. If asked "why the adapter?": the engine is one release ahead of the tooling. (Learn: Feature availability for Data API builder → Unsupported data types.)
- **Hosting:** local for the talk; in Azure it belongs in **Azure Container Apps / App Service** with a managed identity + VNet integration (architecture slide shows both).

### Verify the surface (off-stage)
`pwsh ./build/dab/probe-mcp.ps1` → lists the live MCP tools (expect **12**: 7 generic + 5 read/AI).
