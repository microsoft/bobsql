# W25 — The Developers Guide to Azure SQL Hyperscale — Outline (working)

**75 minutes · Intermediate · developer audience.** Built on the existing deck
`Azure SQL Hyperscale The Cloud Database for the era of AI.pptx` (34 slides). This
outline maps that deck to the VS Live session, sets timing, and marks demo state.

## Ground rules (locked with author 2026-07-14)

- **Demos are Hyperscale-only.** No side-by-side other-tier demos.
- **"Live" = already deployed / already recorded.** App flows, portal, and the
  scale/HTAP story run from **recordings** or the **pre-deployed** `wardgeneral`
  environment — nothing is provisioned on stage.
- **AI is a tease, not a deep dive (2026-07-19).** The AI story (vectors, MCP, agents)
  runs deep in the **keynote the next day** — here it's a short teaser that points to it.
  One short beat only; do not rebuild the keynote on this stage.
- **Audience = developers who already know on-prem SQL Server (2026-07-19).** Frame
  *every* beat as a delta: "here's what you already do on your on-prem box, and here's
  what's different / new / better in Hyperscale." Security, HA, and new T-SQL are all
  told as "what changed vs the SQL Server you run today."
- **AI Agents:** *may* run live (SQL MCP / agent). **TBD** — build a recording as the
  safety net regardless.
- **Scenario = Collier Health / Ward General (switched 2026-07-19).** This talk now
  reuses the **book's** healthcare scenario (`collierhealth` server / `wardgeneral`
  database) and the book's **Ch 4 app** (`wardgeneral-app`, .NET 10 +
  `Microsoft.Data.SqlClient`, stored-proc data access) — written once, used for the book
  *and* every delivery of this session. This **reverses** the earlier "Zava Lending, book
  scenario stays in the book" rule: the keynote's AI demo is Zava, so a healthcare
  scenario here has zero overlap. All Zava / DAB references below are **superseded** and
  pending rewire; the deck's Zava data must be reskinned to Ward General. Book boundary
  preserved: the app's **CRUD** core is the Ch 4 deliverable; the **clinical-notes AI**
  feature is the Ch 6 extension — the talk shows both, the book keeps them in their chapters.

## Deployed environment (Collier Health / Ward General — to confirm/provision)

The book's healthcare database. **Schema + seed already authored and validated**
(`hyperscalebook/examples/ch02-getting-started/`, `01-schemas.sql`→`05-seed.sql`);
whether a live Azure instance is currently provisioned is **TBD — confirm or deploy
before the dry-run** (`examples/ch02-getting-started/provision-hyperscale.ps1`).

| Resource | Value (book-locked naming) |
|---|---|
| Logical server | `collierhealth` / `collierhealth.database.windows.net` (the health *system*) |
| Hyperscale database | `wardgeneral` (the flagship hospital / workload) |
| Resource group | `rg-collierhealth` |
| App | `wardgeneral-app` — .NET 10 + `Microsoft.Data.SqlClient` (raw ADO.NET, no ORM), stored-proc data access |
| App identity | `id-collierhealth` managed identity, Entra-only auth (no SQL logins) |
| Schema | `clinical` + `ops`, 13 tables; `clinical.vPatientChart` chart view; native `json` on `Patient.InsuranceJson`, `Encounter.IntakeJson`, `LabResult.ResultJson`; `ClinicalNote` free text; `Observation` high-ingest |
| Stored procs | `GetPatientChart`, `GetPatientChartByBed`, `SearchEncounters`, `AdmitPatient`, `DischargePatient`, `RecordVitals`, `PlaceMedicationOrder`, `FileLabResult`, `AddClinicalNote`, `AddDiagnosis`, `RecordAllergy` |
| App code (to build) | `hyperscalebook/examples/ch04/app/` (empty today) |

> **No DAB Container App dependency anymore.** The app is a first-party .NET app calling
> stored procs directly. The AI beat (clinical-notes vector search) is T-SQL + an optional
> agent, not the retired Zava DAB / MCP container.

## The two demo pillars (from the deck)

> **Zava-era (superseded 2026-07-19).** The `.pptx` still carries Zava data; its
> *structure* survives but the scenario reskins to Ward General (patient charts; HTAP =
> bedside OLTP by day + overnight analytics / ETL on the same `wardgeneral` DB). The
> four-verb spine below is authoritative; this is deck-structure reference only.

The deck is organized around two demo payoffs:
1. **"Is it Hyper or Scale? Why not Both?"** — elastic scale + HTAP under real load
   (reskin to `wardgeneral`: 32 → 192 vCores, high transaction volume, OLTP by day +
   analytics / ETL at night).
2. **"Hyperscale knows AI"** — JSON, vector search (DiskANN / `TOP … WITH APPROXIMATE`),
   SQL MCP.

---

## Proposed reframe — the four developer verbs (author idea, 2026-07-15)

> **Five sections locked (2026-07-19):** **Fundamentals → Secure it → Scale it → Make it
> HA → Modernize it (incl. AI)**. "Fundamentals" is the on-ramp (title/hook + what
> Hyperscale is); the four verbs are the spine. See the Time budget table below.

Re-label the spine from the deck's two *feature* pillars to four *developer-outcome*
verbs — what a dev actually has to do to ship an app: **Secure it · Scale it · Make it
Highly Available · Modernize it.** This changes the narrative frame and slots in two new
beats (regex + an explicit security beat). The first three verbs answer the audience's
real objections (security, perf, availability, new skills, "bring my data to AI") *before*
the AI payoff, so "Modernize it" lands on a foundation the audience already trusts.

**One-liner:** *the SQL Server you already run on-prem — now secured, scaled, and made
highly available by the cloud, with new T-SQL you didn't have before — and no new
database to adopt.*

### Rebalance (2026-07-19) — scale big, developers get new surface, AI just teases

The author narrowed the payoff for this developer audience:

- **Scale it** stays the **primary demo** (the one thing you cannot do on-prem: 32 → 192
  vCores with online rescale — a brief reconnect, not a maintenance window — and no hardware to buy).
- **AI shrinks to a tease.** The full vector / MCP / agent story is the **keynote the
  next day** — here it's one short beat that points forward, not a 20-minute segment.
- **The freed time goes to developer-facing beats they can act on Monday:** **Secure it**
  and **Make it HA** (both told as a delta from on-prem), and a new **"new T-SQL"** beat —
  **JSON + Regex** — which is the strongest "look what's new since your on-prem box" moment
  and is safe to run **live in SSMS** (both GA on Azure SQL Database).

| Verb (app perspective) | Deck mapping | Demo state | Role after rebalance |
|---|---|---|---|
| **Secure it** | `wardgeneral-app` managed identity; PHI boundary (`vPatientChart`) + RLS | Build + narrative | **Grow** — real beat, framed as delta from on-prem (Entra/MI = no SQL logins/passwords) |
| **Scale it** | Seg C / Demo 1, slides 9–16 | Recorded / pre-deployed | **Primary demo** — the can't-do-on-prem moment |
| **Make it Highly Available** | "10 reasons" (slide 16) + SLA slide | Narrative / recording | **Grow** — real beat, framed as delta from on-prem (no WSFC/AG you build yourself) |
| **Modernize it — new T-SQL** | Slide 17 + new (JSON, **Regex**) | **Live SSMS** | **New payoff** — JSON + Regex, GA, on-prem delta |
| **Modernize it — AI** | `ClinicalNote` embeddings + vector search (new) | Build, ~5–7 min | Modest beat → keynote (Zava) goes deep |

### Secure it (from the app's perspective)

**On-prem delta:** on-prem you ship a SQL login + password in a connection string and
guard it forever. In the cloud the story is **"no secrets in your app."** The
`wardgeneral-app` connects to `wardgeneral` with a **managed identity** (`id-collierhealth`),
Entra-only — no password, no connection string, nothing to leak. Build out from there:

- Entra-only auth (no SQL logins); managed identity app → DB.
- Healthcare makes the security story land hardest: **PHI**. `clinical.vPatientChart`
  already omits Email / Phone / `InsuranceJson` — a built-in **PHI boundary** (exactly
  what the book's Ch 8 masks). A clean "secure by design" beat.
- Row-level security by provider / department; data classification / masking on PHI
  columns; TDE (on by default in Azure SQL). Named, not deep-dived.
- Private endpoint / no public network path.
- **NEEDS:** one "Secure it" pillar slide. Live beat candidate: show the app's connection
  using managed identity with **no secret in config**, then a PHI column masked for a
  low-privileged user.

### Scale it

Unchanged — Demo 1. 32 → 192 vCores with online rescale (a brief reconnect, no data
movement), HTAP (OLTP
by day + nightly ETL on the same DB), named replicas for read scale-out. Developer
takeaway: **scale is a config change, not an app rewrite.**

### Make it Highly Available (from the app's perspective)

**On-prem delta:** on-prem HA is *your* job — you stand up WSFC, quorum, Availability
Groups, listeners, and rehearse failover yourself. In Hyperscale it's built in; the
developer only codes for the connection. Today this is a bullet in the "10 reasons" list;
as a pillar it needs its own beat. "HA from the app's perspective" = what the *developer*
still owns:

- **99.995% zone-redundant SLA** — the platform-side guarantee (named, not sold on numbers).
- **Read scale-out routing** to named replicas (`ApplicationIntent=ReadOnly`) — an app
  connection-string change, no rearchitecture.
- **Failover groups / geo-replication** — the app keeps one connection endpoint through
  failover.
- **Connection resiliency / retry logic** — the one thing the app *must* own; show the
  `wardgeneral-app` retry pattern (`Microsoft.Data.SqlClient` `SqlRetryLogicOption` /
  the book's canonical `retry-policy.cs`), and what the app sees during a Hyperscale
  scale op or failover.
- **NEEDS:** one slide + likely a recording (failover is not a live-on-stage beat). The
  read-scale-out connection-string change is the most showable, lowest-risk live element.

### Modernize it — new T-SQL, then one database / many surfaces, then AI

Three beats, all on the **same `wardgeneral` stored procs** the app already calls: (1) new
T-SQL the audience can use immediately, (2) the **app → DAB → MCP** surface progression,
(3) a real-but-modest AI beat.

**Beat 1 — New T-SQL, live SSMS against `wardgeneral` (the "what's new since your on-prem box"):**

- **JSON** — native binary `json` type (SQL Server 2025 / Azure SQL, **GA**), not
  `nvarchar(max)` + `OPENJSON` bolt-ons. The schema already has three: `Patient.InsuranceJson`,
  `Encounter.IntakeJson`, `LabResult.ResultJson`. Store, index, and query them with standard
  T-SQL. Delta: on-prem pre-2025 has no native `json` type.
- **Regex — NEW, GA on Azure SQL Database.** Verified on Learn 2026-07-19:
  `REGEXP_LIKE` / `REGEXP_REPLACE` / `REGEXP_SUBSTR` / `REGEXP_INSTR` / `REGEXP_COUNT` /
  `REGEXP_MATCHES` / `REGEXP_SPLIT_TO_TABLE`. Real Ward General use on **`ClinicalNote`**
  free text: validate / extract MRN, phone, email; pull **BP readings, med doses, ICD-10
  codes** out of note prose — replacing brittle `LIKE` / `PATINDEX` hacks every on-prem
  dev has written. **GA — no preview tag needed.** *Still needs a script + a slide.*
- Same-column synergy: **regex = deterministic extraction, vectors = semantic similarity**
  on the *same* `ClinicalNote` text — this sets up the AI beat.
- Developer takeaway: **brand-new T-SQL surface, zero new dependencies** — it's just the
  engine you already know, with functions on-prem never had.

**Beat 2 — One database, many surfaces: app → DAB → MCP (committed, "Path A").**

The stored-proc design pays off here: DAB and MCP are **added beside** the ADO.NET app,
not a rewrite of it. Same 11 procs, three consumers.

- **App (ADO.NET)** — the Blazor `wardgeneral-app` calls the procs directly ("see the SQL").
- **DAB (Data API Builder)** — a `dab-config.json` maps each proc to **REST + GraphQL**;
  run DAB and `GET /api/PatientChart?EncounterId=…` returns JSON with **no controller
  code**. DAB runs as a container with its **own managed identity** to `wardgeneral`.
- **SQL MCP Server** — DAB 2.0 exposes an `/mcp` endpoint; the *same* configured procs
  become **agent tools** (a flag, not new config). An agent / VS Code calls
  `GetPatientChart` / `SearchEncounters` as tools.
- The progression line: **Blazor + ADO.NET → DAB (REST/GraphQL, no code) → MCP (agent
  tools)** — one Hyperscale DB, four surfaces, zero rewrites.
- **NEEDS a build:** `dab-config.json` for the 11 procs (drafted 2026-07-19, see
  `hyperscalebook/examples/ch04/dab/`); DAB container deploy with managed identity; MCP enabled.

**Beat 3 — AI (real-but-modest; keynote goes deep, on Zava — no overlap):**

- Clinical-notes semantic search: `AI_GENERATE_EMBEDDINGS` over `ClinicalNote`, a native
  `vector` column + DiskANN index, then *"find patients with a similar clinical
  presentation"* — including the money move, **post-filter vs `WITH APPROXIMATE`**
  (filter *during* traversal, e.g. same unit / same diagnosis class).
- Ties Beat 2: the agent reaches the same data via the SQL MCP tools — the DB is the
  app backend, the REST API, *and* the agent's tool surface.
- **NEEDS a build** (new scenario): embeddings model wired to `wardgeneral`, `ClinicalNote`
  embedded, vector index created, a search proc. Book Ch 5 / Ch 6 owns this T-SQL / agent work.

### Open items this reframe creates (to discuss)

1. **Two new slides minimum** — a "Secure it" pillar slide and a "Make it HA" pillar
   slide. Reuse slide 27 art for Secure; the SLA / named-replica art for HA.
2. **Regex beat** — needs a script + a slide, Learn syntax check, and a preview-tag pass.
3. **Segment order & timing** — does Secure/Scale/HA (foundation) run *before* the AI
   demo, and can the 75-min budget absorb two new beats? Likely trims Seg B (architecture,
   slides 6–7) to pay for it.
4. **How much of Secure/HA is live vs recording** — managed-identity + read-scale-out
   connection string are the only realistically-live candidates; failover is a recording.

---

## Time budget — five sections (Fundamentals + four verbs) (75 min, leave ~5–7 for Q&A)

**Authoritative as of 2026-07-19.** Five sections locked with author: **Fundamentals →
Secure it → Scale it → Make it HA → Modernize it (incl. AI)**. Note the order — **Secure
precedes Scale** ("lock it down, then push it hard"). Scale is still the primary demo;
JSON+Regex is the new live beat; AI is a modest ~5–7-min clinical-notes beat (keynote goes
deep on Zava). The detailed deck-mapped sections A–G *below* are **Zava-era and
pre-rebalance** — pending rewrite to this spine *and* the Ward General scenario.

| # | Section | Content | Slides | Min | Demo state |
|----|------|------|--------|----:|-----------|
| 1 | **Fundamentals** | Title + hook (*"you know on-prem SQL Server; here's what the cloud changes"*) + what Hyperscale is vs on-prem (architecture named, not deep-dived) | 1–8 | 11 | — |
| 2 | **Secure it** | Delta from on-prem: Entra/MI = no logins/passwords; PHI boundary (`vPatientChart`) + RLS; TDE, private endpoint | new + 27 | 8 | App + narrative |
| 3 | **Scale it** | **Primary demo** — 32 → 192 vCores + HTAP on `wardgeneral` (the can't-do-on-prem moment) | 9–16 | 15 | Recorded / pre-deployed |
| 4 | **Make it HA** | Delta from on-prem: no WSFC/AG you build; ZR SLA, read scale-out, failover groups; app-side retry | new + 16 | 8 | App + recording |
| 5 | **Modernize it** | New T-SQL live (JSON + Regex on `ClinicalNote`) → **app → DAB → MCP** (one DB, many surfaces) → AI (clinical-notes vector search) | 17 + new | 17 | Live SSMS + app + build |
| — | Close | DP-800, learn-more | 32–34 | 4 | — |

Total ≈ 63 min + Q&A. Fundamentals grounds the on-prem audience; Secure/Scale/HA prove the
platform; Modernize is the developer payoff (new T-SQL) with a modest AI beat that hands
off to the keynote.

---

## A. Title + hook (slides 1–2, 3 min)

- Open on developer pain: every "modern app / AI" talk says adopt a *new* data store —
  vector DB here, document DB there. Sprawl.
- Counter-thesis (the deck's spine): **the SQL database you already have does all of
  it** — JSON, REST, vectors, agents — and **Hyperscale** is what makes it do all of it
  *at cloud scale*. No new database, no abandoning SQL Server.

## B. What Hyperscale is (slides 3–8, 12 min)

- **Slide 3–4 — GA + capabilities.** Cloud-native SQL at any scale; the number wall:
  128 TB, 192 vCores, 30+ named replicas, 99.995% ZR SLA, 150 MiB/s log throughput.
  Frame each as a developer "so what," not a spec.
- **Slide 5 — "Is it SQL Server?"** The quiet superpower: same engine, same T-SQL,
  same SQLOS/QP, apps migrate without code changes. *The "Hyper" is in the
  architecture, not the engine.*
- **Slide 6–7 — How it's unique + architecture diagram.** One diagram: compute /
  page servers / log service / RBPEX / Azure Storage; HA + named replicas. **Named,
  not deep-dived** — developer cut, not the book's Ch 3.
- **Slide 8 — "Isn't it expensive?"** Teach the model, not numbers: pay for storage you
  use, no engine license fee, reserved capacity / savings plan, pay only for HA replicas
  you need, named replicas independently sized.

## C. Demo 1 — Hyper *and* Scale (slides 9–16, 15 min)

- **Slide 9 — demo title:** "Is it Hyper or Scale? Why not Both?"
- **Demo 1 (recorded / pre-deployed):**
  - Slides 10–12 — Ward General patient-chart app + Azure Portal **recordings**: the app under
    load, scale compute 32 → 192 vCores with online rescale (a brief reconnect, no data movement).
  - Slide 13 — workload characteristics: HTAP, 6M+ transactions, 250 → 2,000 concurrent
    users, 6 OLTP query types + nightly ETL batch (5M-row bulk INSERT → CCI). Both
    patterns on the same database, same SQL.
  - Slide 14 — dashboard **recording** (one slide = image to explain, one = click-through).
- **Slide 16 — "Why Collier Health chose Hyperscale" (10 reasons):** 192 vCores, named replicas,
  100 TB no perf cliff, log throughput, native columnstore HTAP, automatic tuning,
  full T-SQL engine, elastic scale, built-in monitoring, 99.995% SLA. Use as the
  segment closer — it *is* the "why Hyperscale mattered here" beat.
- **Developer takeaway:** scale and HTAP are a *config change*, not an app rewrite.

## D. The developer's database + AI surface (slides 17–20, 10 min)

- **Slide 17 — "The developer's database."** The abstract's four beats live here as one
  picture: **JSON** type/index/functions, **Vector** type/index/functions + embeddings,
  **DAB REST & GraphQL**, **SQL MCP Server**, REST endpoints from T-SQL, plus multi-model
  (graph, spatial, ledger, in-memory) and native Aspire / EF Core / Semantic Kernel /
  Agent Framework support. This slide sets up Demo 2.
- **Slide 18 — "Zava is unsure about AI."** The objections: security, perf, availability,
  "why vectors," new skills, responsible AI, "I have to bring my data to AI." Sets the
  tension the AI demo resolves.
- **Slide 19 — Microsoft SQL & AI surface.** Vector search, REST API, T-SQL agentic RAG,
  AI in the engine, dev copilots — across VS Code, GitHub Copilot, SSMS, Azure, Fabric.
- **Slide 20 — AI announcements.** SQL MCP Server via DAB 2.0, DML on VECTOR-INDEXed
  tables, iterative filtering with `TOP … WITH APPROXIMATE`, faster `CREATE VECTOR INDEX`.
  **Re-verify each item's GA/preview status the week of the talk** and update the `*`
  tags (per book preview discipline).

## E. Demo 2 — Hyperscale knows AI (slides 21–28, 20 min)

The abstract's core. Four beats, in order:

- **Slide 21 — demo title:** "Hyperscale knows AI."
- **JSON + REST (DAB):** show native `json` on Zava data, then DAB exposing entities +
  stored procs as REST — **recording** or pre-deployed endpoint. Slide 28 has the
  `dab-config.json` (MCP + REST). *Keep this tight — it's the plumbing for the MCP beat.*
- **Vector search (slides 22–25, the crowd-pleaser):**
  - Slide 22 — Zava operational dashboard **recording**: intelligent search + AI loan
    scoring.
  - Slide 23 — **SSMS, live against pre-deployed env** (or recorded): vector search on a
    **named replica**, INSERTs into a vector-indexed table (DML now supported), and
    `SELECT TOP (N) … WITH APPROXIMATE`.
  - Slide 24 — the money slide: **post-filter vs `WITH APPROXIMATE`** — legacy finds 5
    nearest then filters (0/5 qualify); `WITH APPROXIMATE` filters *during* DiskANN
    traversal (5/5 qualify). This is the developer "aha."
  - Slide 25 — DiskANN index-build benchmark (quantization, 5–10× faster, MVP quote).
- **SQL MCP / agent (slide 28, live-TBD):** the database as an agent tool via DAB SQL MCP
  Server (`describe_entities`, `read_records`, `execute_entity`, etc.). **This is the
  "may run live" beat** — an agent answers a Zava question by calling the DB's MCP tools.
  *Build a recording as the fallback.* "Same database. Same queries. Same performance."
- **Developer takeaway:** app backend, REST API, vector store, and agent tool — one
  Hyperscale database, four roles, all standard T-SQL + tooling.

## F. Responsible AI + why Zava chose it for AI (slides 27, 31, 6 min)

- **Slide 27 — Azure AI Gateway (APIM) + Content Safety.** How governed model access
  works — Entra auth, token rate limit, semantic cache, content safety in/out, managed
  identity (no keys), full audit — **zero code changes** to the .NET Agent Framework /
  T-SQL app. Answers the slide-18 objections.
- **Slide 31 — "Why Zava chose Hyperscale for AI."** The intelligence lives where the
  data lives; any surface, one engine; responsible AI built in. Segment closer.

## G. Close (slides 32–34, 4 min)

- **Slide 32 — DP-800** SQL AI Database Developer certification (call to action).
- **Slide 33 — the one-liner:** Hyperscale = best SQL platform for your AI apps —
  Familiarity, AI, Security, Scalability.
- **Slide 34 — Learn More** links + `aka.ms/bobwardms`.

---

## Demo asset inventory (to confirm / build)

| Beat | Asset | State |
|---|---|---|
| Scale 32→192 + HTAP | `wardgeneral` under load + portal scale recording | **Build** — new scenario; reskin from Zava recordings |
| The app | `wardgeneral-app` (.NET 10, `Microsoft.Data.SqlClient`, stored procs) at `hyperscalebook/examples/ch04/app/` | **Build** — empty today (book Ch 4 deliverable) |
| Secure it | Managed-identity connection (no secret) + PHI mask via `vPatientChart` / RLS | **Build** — needs the app + a security slide |
| Make it HA | Read scale-out (`ApplicationIntent=ReadOnly`) + retry (`retry-policy.cs`) | **Build** — app-side; failover = recording |
| New T-SQL (JSON + Regex) | SSMS scripts on `wardgeneral` (`InsuranceJson`/`IntakeJson`/`ResultJson`; `REGEXP_*` on `ClinicalNote`) | **Build** — schema exists; scripts + slide to write |
| DAB (REST + GraphQL) | `dab-config.json` mapping the 11 procs; DAB container + managed identity | **Build** — config drafted `examples/ch04/dab/`; deploy pending |
| SQL MCP Server | DAB 2.0 `/mcp` over the same procs (agent tools) | **Build** — enable on the DAB deploy |
| AI (clinical-notes vector search) | Embeddings + `vector` index on `ClinicalNote`; search proc; reached via MCP | **Build** — new; book Ch 5 / Ch 6 |

## Pre-flight checklist (run before the talk / dry-run)

1. **`az login`** and select the subscription (confirm which sub hosts `collierhealth`).
2. **Confirm / provision `wardgeneral`** under the `collierhealth` server
   (`examples/ch02-getting-started/provision-hyperscale.ps1`), then deploy schema + seed
   (`01-schemas.sql`→`05-seed.sql`) and verify (`connect-and-verify.sql`, `verify-data.sql`).
3. **Confirm the app builds / runs** (`hyperscalebook/examples/ch04/app/`) against
   `wardgeneral` with **managed identity** (no secret in config).
4. **Confirm the new-T-SQL scripts** (JSON + `REGEXP_*` on `ClinicalNote`) run in SSMS.
5. **Confirm the AI beat** — embeddings model reachable, `ClinicalNote` embedded, vector
   index present, search proc returns results.
6. **Re-verify preview tags** (vector index / iterative filtering) against Learn.

## Open decisions for the author

1. **Provision state of `wardgeneral`** — confirm whether a live Azure instance exists or
   must be provisioned from `examples/ch02-getting-started/` before the dry-run.
2. **How far the AI beat goes** — vector-search-only, or + SQL MCP agent hand-off. Keynote
   (Zava) is the deep dive; keep this modest.
3. **Deck rebuild** — the `.pptx` is Zava-era; its structure survives but all data / screens
   reskin to Ward General. Decide: reskin existing deck vs rebuild.
4. **Reconcile detailed sections A–G** (above) — Zava-era, pending rewrite to Ward General.
5. **DP-800 slide (32)** — confirm the exam is still live / same `aka.ms` link at talk time.
