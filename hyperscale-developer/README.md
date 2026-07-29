# W25 — The Developers Guide to Azure SQL Hyperscale

**Event:** Visual Studio Live! @ Microsoft HQ 2026
**Date:** Wednesday, July 29, 2026 · 3:30pm–4:45pm (75 min)
**Level:** Intermediate
**Track:** Data and Analytics, Microsoft Sessions
**Speaker:** Bob Ward — Principal Architect, Microsoft Azure Data
**Session page:** <https://vslive.com/events/microsofthq-2026/sessions/wednesday/w25-azure-sql-hyperscale.aspx>

## Abstract (as published)

> Azure SQL Hyperscale brings modern cloud and AI capabilities directly into SQL
> based applications. In this developer focused session, you'll learn how
> Hyperscale's architecture enables elastic scale, predictable performance, and cost
> efficient operation while remaining fully SQL Server compatible. We'll cover building
> APIs with JSON, exposing data through REST style access, using vectors for AI
> driven search, and integrating AI agents via SQL MCP—showing how Hyperscale
> supports modern app and AI workflows without introducing new databases or abandoning
> the SQL Server you know and love.

## Contents

- [outline.md](outline.md) — session outline and flow (working document), mapped slide-by-slide to the deck.
- `Azure SQL Hyperscale The Cloud Database for the era of AI.pptx` — the working deck (34 slides).

## Scenario & demo ground rules

- **Scenario (switched 2026-07-19):** the **book's Collier Health / Ward General**
  healthcare scenario (`collierhealth` server / `wardgeneral` database) and the book's
  **Ch 4 app** (`wardgeneral-app`, .NET 10 + `Microsoft.Data.SqlClient`, stored-proc
  data access). Written once for the book, reused for every delivery of this session.
  Reverses the earlier "Zava Lending" rule — the keynote's AI demo is Zava, so a
  healthcare scenario here has zero overlap.
- **Reusable asset:** this talk is built to be **re-delivered at multiple events**, not
  tied to one Zava environment.
- **Demos are Hyperscale-only.** Anything "live" is **already deployed or pre-recorded**;
  nothing is provisioned on stage.
- **Four-verb spine:** *Secure it · Scale it · Make it HA · Modernize it* (JSON + Regex
  live; clinical-notes AI a modest beat that hands off to the keynote). See `outline.md`.
- **The app runs locally, but in reality it belongs in Azure.** For the talk the
  `wardgeneral-app` runs on the presenter's laptop (Kestrel on `https://localhost:7170`)
  purely so it's trivial to build (`build.ps1`) and run (`run.ps1`) on stage. In
  production it would run as an **Azure App Service** (or Container App) — ideally with
  **VNet integration** so it reaches the database over the **private endpoint** and the
  public path can be turned off (see *Row-Level Security* and `deploy/provision-private-link.ps1`).
  Everything else it depends on — the Hyperscale database, managed-identity auth, RLS,
  the private endpoint — already lives in Azure and is unaffected by where the app runs.

- **"Passwordless" ≠ "managed identity on the laptop."** The DAL sets
  `Authentication = ActiveDirectoryDefault` (`WardGeneral.Data/WardGeneralConnectionFactory.cs`),
  which resolves a **credential chain**, not a fixed identity. Running on the presenter's
  laptop there is **no managed identity** — the chain falls through to the developer's
  **Entra login** (`az login`, or the VS / VS Code sign-in). Deployed to Azure App Service /
  Container Apps the *same code* picks up the app's **managed identity** at the top of the
  chain. What's constant either way: **no password, no secret, no key on disk** — only a
  short-lived Entra token; the only difference is *who* issues it (you locally, the platform
  in Azure). So on the laptop your `az login` identity must be a SQL user on `wardgeneral`;
  in Azure you grant the managed identity that same `CREATE USER … FROM EXTERNAL PROVIDER`.

- **First-time setup — trust the local HTTPS cert.** The app runs on Kestrel with the
  ASP.NET Core developer certificate. If the browser shows a **"Not secure"** warning on
  `https://localhost:7170`, trust the dev cert once (then fully close and reopen the browser):
  ```powershell
  dotnet dev-certs https --trust
  ```


## Build everything — end-to-end deploy (in order)

Every box in the architecture diagram (`architecture/wardgeneral-architecture.svg`)
is produced by the ordered steps below. Each step is a **PowerShell script** — no
step is "run this by hand." The three deploy skills point here for the canonical
order; run the steps top-to-bottom on a fresh environment.

**Prerequisites (once):** PowerShell 7+ (`pwsh`), Azure CLI 2.60+, .NET 10 SDK,
and `az login` as a member with rights to the subscription/RG. All scripts are
**passwordless** (Entra tokens / managed identity) and **idempotent** (safe to
re-run). Scripts live in `build/deploy/` unless noted.

| # | Layer (arch diagram) | Command | Skill |
|---|---|---|---|
| 1 | **Hyperscale server + `wardgeneral` DB** (+ server MI, firewall) | `provision-hyperscale.ps1` *(set `ADMIN_OBJECT_ID`, `SQL_ADMIN_PASSWORD` first)* | deploy-wardgeneral-db |
| 2 | **Schema + seed** (tables, views, procs, synthetic data) | `deploy-sql.ps1 -Scripts 01-schemas,02-tables,03-views,04-procedures,05-seed` | deploy-wardgeneral-db |
| 3 | **Verify** DB tier + data | `deploy-sql.ps1 -Scripts connect-and-verify,verify-data` | deploy-wardgeneral-db |
| 4 | **Azure AI layer** — Foundry (gpt-5 + embeddings), server MI, RBAC *(+ APIM gateway + content safety)* | `azureaideploy.ps1 [-Gateway -ContentSafety]` | deploy-wardgeneral-ai |
| 5 | **In-engine embeddings + vector index** | `deploy-sql.ps1 -Scripts 06-ai-embeddings` → `generate-embeddings.ps1` *(~3 h, resumable)* | deploy-wardgeneral-ai |
| 6 | **In-engine clinical assistance** (RAG → gpt-5) | `deploy-sql.ps1 -Scripts 07-ai-assistance` | deploy-wardgeneral-ai |
| 7 | **Gateway credential + gateway-aware proc** *(only if step 4 used `-Gateway`)* | `run-ai-gateway-e2e.ps1 -SkipSetup` *(deploys `09` + verifies a live call)* | deploy-wardgeneral-ai |
| 8 | **DAB + SQL MCP** (REST/GraphQL/MCP agent surface; deploys `08` + `11`) | `build/dab/setup-dab.ps1` | — |
| 9 | **Row-Level Security** (Secure it) | `deploy-sql.ps1 -Scripts 10-row-level-security` | — |
| 10 | **App** (Blazor chart) | `build/build.ps1` → `build/run.ps1` | wardgeneral-app |

**Optional per-section Azure resources** (shown live on stage; deploy ahead if you
want them pre-built):

| Section | Layer | Command |
|---|---|---|
| Secure it | TDE customer-managed key (BYOK) | `provision-tde-cmk.ps1` |
| Secure it | Private endpoint / Private Link | `provision-private-link.ps1` |
| Scale it | Named replica for read-scale / research | `provision-research-replica.ps1` (+ `08-research-vector-search.sql` via `setup-dab.ps1`) |

**Minimum path to a running app:** steps 1 → 2 → 10 (schema + app, no AI). Add
steps 4 → 6 for the AI card; add step 7 for the governed gateway path; add step 8
for the agent surface; add step 9 for RLS.

**Tear down (local + billable Azure):** `build/teardown.ps1` stops the app/DAB and
cleans build artifacts (local only — never the shared DB). The always-on billable
resource to remember is the APIM gateway:
`az apim delete -n collierhealth-ai-gateway -g rg-collierhealth --yes --no-wait`.


## Source material

- Working deck (above) — the ground-truth story and demo structure.
- Book: `hyperscalebook/manuscript/ch01-introduction/` and `ch02-getting-started/` — framing, "is it SQL Server?", pricing model, preview-tag discipline.
- Reusable demo assets: `presentations/build2026/BRK223/` (DAB REST + SQL MCP over Azure SQL), `presentations/coreengine/aci/` (Automatic Index Compaction on Hyperscale).
- Prior Hyperscale material: `presentations/sqlbits2026/hyperscale/` (build-your-own-hyperscale cost/architecture argument).

## Status

- [x] Folder created, abstract captured.
- [x] Deck dropped in; outline mapped to deck.
- [x] Reframed to four-verb spine (Secure / Scale / HA / Modernize).
- [x] Scenario switched to Collier Health / Ward General (2026-07-19).
- [ ] Ch 4 app (`wardgeneral-app`) built.
- [ ] `wardgeneral` provision state confirmed.
- [ ] New-T-SQL (JSON + Regex) scripts + slides built.
- [ ] Deck reskinned from Zava → Ward General.
- [ ] Preview tags re-verified week of talk.

## Diagnostics

Quick health checks you can run **without the Blazor app** — handy after a
deploy, a model/gateway change, or a database refresh. They live in
`build/diagnostics/`.

- **`test-ai-assistance.ps1`** / **`test-ai-assistance.sql`** — exercises the
  in-engine clinical-assistance path end-to-end: calls
  `clinical.GenerateClinicalAssistance` for one encounter (RAG over the clinical
  notes → gpt-5 via Microsoft Foundry) and proves the tamper-evident audit row
  landed in the append-only ledger table `clinical.AIAssistanceLog`. This is the
  exact stored proc the app's "Get AI assistance" card runs.

  ```powershell
  # PowerShell driver (handles the Entra access token via az login + sqlsim):
  ./build/diagnostics/test-ai-assistance.ps1                 # auto-picks an Active encounter with notes
  ./build/diagnostics/test-ai-assistance.ps1 -EncounterId 249
  ```

  Or run `test-ai-assistance.sql` directly in SSMS or the VS Code MSSQL
  extension (Entra / passwordless). Expect one result row (triage flag, grounded
  summary, note IDs, latency) and `AuditRowAppended = yes`. A graceful
  "AI assistance unavailable …" summary means a transient Foundry error — re-run.

## Feature flags (progressive reveal)

The chart app surfaces its **later** features behind flags in the
`Features` section of `build/src/WardGeneral.Web/appsettings.json`:

| Flag | Chart panel | Backing SQL |
|---|---|---|
| `Features:NoteSignals` | "From the note · `REGEXP_*`" — regex-extracted vitals / pain / follow-up | `clinical.vChartNoteSignals` |
| `Features:AiAssistance` | "AI assistance" card — vector search + gpt-5 | `clinical.GenerateClinicalAssistance` (+ embeddings) |

Both default **ON**, so for the talk the app **just works** — everything is
already deployed. Flip a flag off (config file, or env var
`Features__NoteSignals=false`) to hide a panel.

**To enable a feature** (talk or book) — three steps, in order:

1. **Deploy the backing SQL** (e.g. `03-views.sql`/`04-procedures.sql` for the
   regex panel; `06`/`07` for AI assistance).
2. **Flip the flag** to `true` in `appsettings.json` (or set the env var).
3. **Restart the app** (`build/run.ps1`).

The restart is required: the flags bind through `IOptions<FeatureFlags>`, which
ASP.NET Core resolves **once at startup** — config changes aren't picked up while
the app is running.

Two things gate each panel, and **both** must be true — the SQL is the feature,
the flag is when you reveal it:

1. **The database capability** — the panel's backing SQL is deployed.
2. **The flag** — turns the panel on in the UI.

Order matters: **deploy the SQL first, then flip the flag and restart.** The
data-access layer reads the backing columns column-tolerantly, so a flag left on
before its SQL exists degrades gracefully (the regex panel simply self-hides; the
AI card's button reports "unavailable" rather than crashing). This is also how
the *book* reveals these features chapter by chapter with no app-code changes —
deploy the chapter's `.sql`, flip the flag, restart. **JSON is intentionally not
flagged**: it's foundational to the base chart (Chapter 2), so it is always on.

## Row-Level Security (Secure it)

The app connects as **one managed identity** (trusted subsystem — passwordless,
no per-user logins). Row-Level Security pushes the "who can see which patients"
decision out of the app and into the **engine**: on every pooled connection the
data-access layer stamps the acting clinician into `SESSION_CONTEXT`, and a
security policy on `clinical.Encounter` filters rows server-side.

- **Backing SQL:** `build/sql/10-row-level-security.sql` — `security.fn_encounterAccess`
  predicate + `security.EncounterAccessPolicy` (`FILTER` + `BLOCK`, `STATE = ON`).
  Because it's applied to `clinical.Encounter`, the filter **propagates** to
  `clinical.vPatientChart` and `ops.vBedCensus` — the chart *and* the unit board
  shrink to the acting provider.
- **Config** — one key, `RowLevelSecurity:Enabled` (default **on**). When on, the
  data layer stamps the acting identity held in the per-circuit `AccessContext`.

**The live demo — a "Viewing as" selector.** RLS is **on by default**, and the
default identity is **Admin → every patient** (the "before" picture). The unit
board has a **Viewing as** dropdown of attendings. Pick one — say *Dr. Ginger
Ward* on unit *4 North* — and the board redraws to **only her 10 patients**;
pick *All providers · Admin* to see everyone again. A badge shows the active
identity (`RLS · Dr. Ginger Ward — scoped`).

**No restart, no explicit reconnect.** The data layer opens a fresh pooled
connection per query and stamps `SESSION_CONTEXT` on each open; `sp_reset_connection`
clears it on pool reuse. So switching "Viewing as" simply re-stamps on the next
board reload — the "reconnect" is automatic and per-operation. (This is exactly
the real-world middle-tier pattern: one app identity, per-request `SESSION_CONTEXT`.)

**Fail-open by design (demo DB):** the predicate allows *all* rows when **no**
context is set, so the `diagnostics/` scripts, `sqlsim`, and background jobs are
unaffected — the always-on policy is harmless until a session opts in. In the app,
Admin is stamped explicitly (`Role = 'Admin'`), so "see everything" is a real
authorization decision, not an accident. A **production** system would flip the
predicate to **fail-closed** (deny when no context). Verify the engine behavior
with `build/diagnostics/verify-rls.sql`.


## Data API Builder + SQL MCP (Modernize it — the agent surface)

The Blazor app calls the `clinical.*` stored procedures directly (ADO.NET).
**Data API Builder (DAB)** takes those *same* procedures and exposes them — with
**no middle-tier code** — as **REST**, **GraphQL**, and, most interestingly,
**MCP tools an AI agent can call**. One stored-proc contract, three consumers.
That's the payoff of "procs for everything": a second (and third) consumer is free.

DAB is **not a layer under the app** — it's a *parallel* consumer of the same
contract, aimed at agents and other clients.

### Prerequisites
- .NET SDK (for the DAB CLI) and `az login` as a database member (passwordless).
- The Ward General database deployed (see `deploy-wardgeneral-db`), **plus** the two
  DAB-specific SQL objects (deployed by `setup-dab.ps1`, below):
  - `sql/08-research-vector-search.sql` — `clinical.SearchSimilarNotes(@QueryText, @TopK)`.
  - `sql/11-dab-adapters.sql` — see *native-JSON adapters* below.

### Set up (once, reproducible on any machine)
```powershell
./build/dab/setup-dab.ps1     # installs the DAB CLI, deploys 08 + 11, validates config
```

### Run it (local, like the app)
```powershell
./build/dab/run-dab.ps1       # http://localhost:5000  (REST /api · GraphQL /graphql · MCP /mcp)
```
Passwordless (`Authentication=Active Directory Default`). For the talk DAB runs
**locally**, exactly like the app; in production it belongs in **Azure Container
Apps** (or App Service) with a **managed identity** and **VNet integration** to
reach the private endpoint — the architecture slide shows both.

### Wire it into VS Code (the MCP client)
- **Single folder:** open `build/` in VS Code — `build/.vscode/mcp.json` is
  auto-discovered.
- **Multi-root `.code-workspace`:** VS Code does **not** read a folder's
  `.vscode/mcp.json` in multi-root mode. Put the same `servers` block under a
  top-level `mcp` key in the `.code-workspace` file (that's how `bwsql.code-workspace`
  is set up).
- Then **MCP: List Servers** → start it (shows as **"SQL MCP Server"** — that's DAB's
  own advertised name; not renamable in v2.0.9), and enable its tools in the chat's
  **Configure Tools**.

### Demo it (Copilot Chat → Agent mode)
No need to name the server — the tool descriptions are written for routing:
- *"Find historical clinical notes similar to 'elderly chest pain with elevated troponin', top 5."* → `search_similar_notes` (vector search, ~4s).
- *"Show the full clinical chart for encounter 249."* → `patient_chart`.
- *"Give me the AI clinical assistance for encounter 249."* → `clinical_assistance` (RAG + gpt-5, ~13s — the finale).

Cold-start note: the **first** tool call after connecting can whiff (VS Code is
establishing the session) — just send it again. Fire one throwaway call during
setup so the connection is warm before you present.

### Stage safety — read-only by default
The 8 write procs (admit/discharge/vitals/meds/labs/notes/diagnosis/allergy) are
locked: hidden from MCP (`custom-tool: false`) **and** gated to the `authenticated`
role, so the unauthenticated demo returns **403** on every surface. The agent can
read, search, and run AI, but **cannot mutate** patient data. To enable a live-write
demo, flip those entities back to `anonymous` + `custom-tool: true` in
`build/dab/dab-config.json` and restart DAB.

### Native-JSON / vector adapters (why `11-dab-adapters.sql` exists)
DAB (all versions, incl. 2.0.9) does **not** support the SQL Server 2025 native
`json` or `vector` types
([Learn — Feature availability](https://learn.microsoft.com/azure/data-api-builder/feature-availability#unsupported-data-types)).
It introspects every proc parameter and result column at startup and aborts on
those types. Ward General uses native `json`/`vector` **on purpose**, so:
- `SearchSimilarNotes` dropped its unused `@QueryVector vector` parameter (embeds
  inline from `@QueryText` via a local).
- `11-dab-adapters.sql` adds four thin **boundary adapters** — `GetPatientChartApi`,
  `GetPatientChartByBedApi` (CAST the 11 json columns → `nvarchar(max)`), and
  `AdmitPatientApi`, `FileLabResultApi` (accept json as `nvarchar(max)`, cast on the
  way in). The **app's own procs are untouched** — they stay the native-`json`/`vector`
  showcase; DAB points at the `*Api` versions.
- The teaching point: the engine is one release ahead of the tooling, so you
  **serialize native types to text at the API boundary** (exactly what the TDS
  driver does implicitly for older clients). Delete this file when DAB gains native
  support.

### From a dev test to a real app — Microsoft Agent Framework / Foundry
Driving the tools from VS Code Copilot is the **developer inner-loop test**. The
*same* MCP endpoint is how a real application's agent uses the database:

- **Microsoft Agent Framework** (the .NET / Python agent SDK): your app's agent
  registers the DAB **MCP server as a tool provider** and calls `search_similar_notes`,
  `patient_chart`, `clinical_assistance`, etc. as tools — same endpoint, same
  contract, now inside *your* code instead of Copilot Chat.
- **Microsoft Foundry Agent Service**: add the DAB server as a **custom MCP tool** on
  a hosted Foundry agent; the agent (with your model, instructions, and guardrails)
  invokes the same tools. DAB itself documents both quickstarts (VS Code, and Foundry).
- **Production shape:** DAB hosted in **Azure Container Apps** (managed identity +
  Private Link), your agent app (Agent Framework or Foundry) connects to its `/mcp`
  URL, and the write tools re-enabled behind **Entra auth + roles** instead of the
  read-only anonymous demo lock.

So the progression is: **VS Code Copilot (inner-loop) → your app's agent via Agent
Framework or Foundry (production)** — one DAB MCP endpoint the whole way. *(Wiring
an Agent Framework / Foundry client is a book-chapter extension; not built in this kit.)*

### Verify without VS Code
- `build/dab/probe-mcp.ps1` — lists the live MCP tools (expect 12 in read-only mode).
- `build/dab/probe-toolcall.ps1` — actually invokes `search_similar_notes` over the
  MCP protocol (`tools/call`), independent of any client.
- `build/dab/probe-tooldescs.ps1` — dumps each tool's description (routing metadata).






