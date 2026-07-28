# Ward General / Hyperscale-developer talk — Backlog

Open questions and not-yet-built pieces for the talk + the *Azure SQL Hyperscale
Unveiled* book reuse. Newest items at the top of each section.

## Candidate demo / coverage topics (may not all be shown)

Added 2026-07-21. Platform / security / scale capabilities to cover in the talk
and/or book. **We may not show all of these live in a demo** — some may be
slides, recordings, or book-only. Decide coverage per item (live demo vs.
recording vs. slide vs. book-only).

1. **Duplicate / near-identical clinical notes** — **[FIXED 2026-07-22]** Root cause:
   the seed built every note as a deterministic function of `EncounterId` through
   correlated `CHOOSE(... % n)` picks, collapsing 60k rows to **3,150 distinct
   notes (94.75% dupes)** with one shared timestamp. Rewrote the generator in
   [build/sql/05-seed.sql](build/sql/05-seed.sql) §10: notes are now **anchored to
   the encounter's primary diagnosis** (coherent + they cluster by condition for
   vector search) with **independent per-fragment `ABS(CHECKSUM(NEWID()))`**
   randomness and a randomized `CreatedAt`. Validated: **60,000 / 60,000 distinct
   (0% dupes)**, REGEXP tokens still extract, grammar clean. Live table re-seeded
   via [build/sql/reseed-notes.sql](build/sql/reseed-notes.sql) (targeted — patients
   /encounters/labs untouched); embeddings rebuilding via `deploy/generate-embeddings.ps1`
   (async). *Remaining:* let the embedding pass finish + `CREATE VECTOR INDEX`, then
   re-verify with [build/sql/_dupe-check.sql](build/sql/_dupe-check.sql).
2. **Private Link** — **[DEPLOYED 2026-07-21]** private endpoint `pe-collierhealth-sql`
   on the `collierhealth-17` logical server (group-id `sqlServer`, so it covers
   `wardgeneral` and any same-server named replica). Private IP `10.42.1.4` in
   `vnet-collierhealth/snet-sql`; Private DNS `privatelink.database.windows.net`
   A record `collierhealth-17 -> 10.42.1.4`. **Public access left ENABLED** so the
   laptop demo keeps working — a private endpoint is only reachable from inside the
   VNet. Script: `build/deploy/provision-private-link.ps1` (idempotent-ish; has a
   `-DenyPublic` switch + commented teardown). To go *fully* private-only you must
   run the app from inside the VNet (VM / App Service VNet-integration / VPN), then
   `-DenyPublic`. Show it in the portal: collierhealth-17 > Networking > Private
   access (connection = Approved).
2. **Demo steps and recordings** — a written run-of-show (click-by-click demo
   script) plus pre-recorded fallbacks for every live beat (demos are
   Hyperscale-only and pre-deployed; nothing provisioned on stage). **[STARTED
   2026-07-21]** `DEMO-RUNBOOK.md` created — pre-flight checklist + the **DAB + MCP
   beat fully written** (prompts, tools, close, stage-safety note); other beats
   (Build/Secure/Scale/Modernize/AI) are scaffolded placeholders to draft. 🎥
   recordings still TODO.
3. **Microsoft Defender for SQL** — threat protection / vulnerability assessment
   on the Hyperscale database. "Secure it" story. **[COVERAGE: SLIDE-ONLY]** Not a
   live demo — goes on the **"Secure it" slide** as a bullet (Bob, 2026-07-21).
   *TODO: help Bob build the "Secure it" slide bullets* (candidates so far:
   passwordless / Entra-only auth · Row-Level Security via SESSION_CONTEXT ·
   versionless customer-managed key TDE (BYOK) · Private Link / private endpoint ·
   append-only ledger audit · **Microsoft Defender for SQL** · Purview/auditing).
4. **Versionless TDE with customer-managed key (CMK)** — **[DEPLOYED 2026-07-21]**
   TDE protector on `collierhealth-17` switched to a customer-managed RSA key in
   Key Vault `kv-collierhealth-tde` (purge-protected), supplied as a **versionless**
   key id with auto-rotation. Script: `build/deploy/provision-tde-cmk.ps1`.
   Finding: versionless is an **input** feature (GA Mar 2026) — Azure SQL resolves it
   to the current version and stores a *versioned* protector (portal/CLI show a
   version); it then always uses/auto-follows the latest enabled version. Needed
   `az upgrade` (2.67 → 2.88; 2.67 rejected the versionless id client-side). Show it:
   server > Security > Transparent data encryption (Customer-managed key + Auto-rotate).
5. **Serverless and Elastic Pools** — the compute/cost-elasticity story
   (serverless auto-pause/scale; elastic pools for many hospitals). Named in Ch 2,
   deployed later (Ch 10) as Collier Health scales to many hospitals. Ties to
   "Scale it" + the cost model. **[PARTIAL 2026-07-21]** A **serverless named
   replica** `wardgeneral-research` (HS_S_Gen5_8, autoscale 1→8 vCores) is now LIVE
   on `collierhealth-17` — see `build/deploy/provision-research-replica.ps1`. NOTE:
   Hyperscale serverless **autoscales but does not auto-pause** (auto-pause is GP
   only), so it idles at 1 vCore. **Elastic pools: [COVERAGE: SLIDE-ONLY]** — a
   talking point on the **"Scale it" slide** (many hospitals / many databases
   sharing a pool of compute), not a live demo (Bob, 2026-07-21).

Deliverable per item: decide **coverage mode** (live / recording / slide /
book-only), and for anything live, the deploy + verify steps.

## Open design questions

### 0. Where to use the new SQL Server 2025 regex T-SQL functions
SQL Server 2025 / Azure SQL adds native **regular-expression T-SQL functions**
(e.g. `REGEXP_LIKE`, `REGEXP_REPLACE`, `REGEXP_SUBSTR`, `REGEXP_INSTR`,
`REGEXP_COUNT`, `REGEXP_MATCHES`, `REGEXP_SPLIT_TO_TABLE` — **confirm exact names
and signatures against Microsoft Learn before writing any**). Find where they
earn their keep in the app instead of hand-rolled `CHARINDEX` / `SUBSTRING` /
`PATINDEX` / `LIKE` / `STRING_SPLIT`.

Candidate spots to evaluate:
- **Mining `ClinicalNote.NoteText`** — the schema comment already says it's
  "regex-mined." Pull structured signals from free text: vitals (`120/80`),
  numeric lab values + units, medication doses, follow-up dates, ICD-ish codes.
  Good fit for the retrieval/AI story (regex to pre-filter or extract, vector
  search to rank).
- **Stripping the ```json fence** in `clinical.GenerateClinicalAssistance` —
  today it uses `CHARINDEX`/`SUBSTRING` to unwrap ```` ```json … ``` ````. A
  single `REGEXP_SUBSTR` for the `{ … }` body would be cleaner and more robust.
- **Boundary validation/normalization** — MRN format, phone, email at the
  system edge (not in the hot path).
- **Splitting** case-summary / note text on natural delimiters where
  `STRING_SPLIT` can't (multi-char or pattern separators).

Deliverable: a short "regex vs. classic string functions" decision (readability,
plan/perf, when regex is overkill) plus 1–2 concrete uses wired into the demo —
ties to the Ch 5 T-SQL story. **Verify every function name/signature on Learn
first** (per the repo's T-SQL authoring rule).

**[DONE 2026-07-21] Wired into the app (not just a live SSMS demo).** New view
`clinical.vChartNoteSignals` runs `REGEXP_SUBSTR` (RE2, Learn-verified signature
`REGEXP_SUBSTR(str, pattern, start, occurrence, flags, group)`) over the latest
note's `NoteText` to extract BP, HR, temp, RR, SpO2, **pain score**, and the
**follow-up** instruction into a structured `json` column. It flows through
`vPatientChart` → `GetPatientChart`/`GetPatientChartByBed` → the DAL
(`NoteSignals` model) → a "From the note · extracted in-engine with REGEXP_*" card
on the bedside chart, right above the free-text notes. Deployed live + verified
(enc 249 → `BP 147/79, HR 103, Temp 37.0, RR 17, SpO2 97, Pain 4/10, "Follow up
with primary care within seven days."`); app builds 0/0 and renders. Story: **one
`NoteText` column, two techniques** — `REGEXP_*` = deterministic extraction you can
trust; the DiskANN vector index = fuzzy semantic recall. Pain score + follow-up
exist ONLY in prose (no structured column), so regex is the only way to query
them. Architecture SVG pill retargeted from the aspirational "MRN / BP / ICD-10"
to what the prose actually contains: "BP · HR · pain · follow-up". **Still open:** a
standalone live-SSMS regex script + slide for the "Modernize it" beat (the app use
is the durable one; the SSMS script is the on-stage teaching moment).

### 0b. Ledger table for a tamper-evident audit trail
Use an **Azure SQL ledger** feature (append-only or updatable ledger tables +
database ledger digest) as a security story for the talk/book. The natural
candidate is **`clinical.AIAssistanceLog`**: an append-only, cryptographically
verifiable record of every AI assistance call (inputs, model, response, suggested
triage flag) is exactly the kind of audit trail compliance wants — it proves the
log wasn't altered after the fact. Evaluate:
- Make `clinical.AIAssistanceLog` an **append-only ledger table** (it's
  insert-only already — a good fit; updatable ledger would be overkill).
- Where the **ledger digest** is published/verified (and who verifies it).
- **Confirm ledger support + any Hyperscale caveats on Microsoft Learn** before
  writing DDL (ledger + Hyperscale interaction, backup/restore, and
  `ALTER TABLE ... ENABLE LEDGER` vs. create-time only).
- Tie-in: pairs with the "Secure it" narrative and the human-in-the-loop framing
  (the audit trail is *provably* intact).

Deliverable: a recommendation on making the AI audit log append-only ledger, with
the verification-workflow sketch and the Learn-checked Hyperscale caveats.

**[DONE 2026-07-21]** `clinical.AIAssistanceLog` is now an **append-only ledger
table** (`WITH (LEDGER = ON (APPEND_ONLY = ON))`) in `build/sql/07-ai-assistance.sql`,
deployed live and verified (`ledger_type_desc = APPEND_ONLY_LEDGER_TABLE`, ledger
view `AIAssistanceLog_Ledger`, `ledger_start_*` columns). Proven on Hyperscale via
a throwaway repro (CREATE/INSERT/DROP OK; UPDATE + DELETE blocked). Ledger is
added to the architecture SVG under SECURE IT. Caveats confirmed on Learn: a
regular table **can't** be converted — must create-new (so we drop+recreate; the
synthetic rows were disposable); no TRUNCATE/UPDATE/DELETE; one-way. The database
ledger **digest** verification (`sp_verify_database_ledger`) is **out of scope** —
the append-only table itself is the security story for the talk/book.

### 1. Managed identity for DB access vs. per-user authorization
The app connects to `wardgeneral` with a **single managed identity** (passwordless,
no secrets — great for the "Secure it" story). But a real hospital needs
**different people to see different things**: an attending sees their unit's
charts, a researcher sees de-identified notes only, a ward clerk sees the bed
board but not clinical notes. One app identity ≠ per-user permissions.

**[DONE — trusted subsystem + `SESSION_CONTEXT` + RLS, shipped.]** The recommended
pattern is built and verified end-to-end: `build/sql/10-row-level-security.sql`
(`security.fn_encounterAccess` predicate + `security.EncounterAccessPolicy`,
`FILTER` + `BLOCK`, `STATE = ON` on `clinical.Encounter`), and the DAL
(`ChartRepository.OpenWithContextAsync`) stamps `ProviderId` / `Role` into
`SESSION_CONTEXT` on every pooled connection when `RowLevelSecurity:Enabled`.
Because the policy sits on `clinical.Encounter`, the filter propagates to
`clinical.vPatientChart` and `ops.vBedCensus` — chart *and* unit board scope to
the acting provider. Fail-open when no context (so RLS-off app / diagnostics /
`sqlsim` see all); production would go fail-closed. Proven: SQL 40 000 → 45 for
provider 3, and the RLS-on board on *4 North* shows only Dr. Ginger Ward's 10 beds.

**App UX shipped & working:** RLS is **on by default** (default identity Admin →
all patients) with a live **"Viewing as"** provider dropdown on the unit board —
pick an attending and the board/charts filter to them in the engine, **no restart**
(the DAL re-stamps `SESSION_CONTEXT` on the next pooled connection). Verified in
the browser: 4 North 17 beds (Admin) → 10 beds (Dr. Ginger Ward) → back to 17.
Documented in the kit README (*Row-Level Security*) and the `wardgeneral-app` skill.

**Still open (future / book depth):** how the OTHER options compare, for the
"who enforces what" table:
- **Entra group → database role** mapping, with the *user's* Entra token used to
  connect (per-user principals in the DB) instead of a shared MI — trades
  connection pooling for real DB-enforced identity.
- **On-behalf-of / Entra passthrough** (user token flows to SQL) vs. the
  **trusted subsystem** we shipped (MI + app-stamped `SESSION_CONTEXT`). Name the
  trade-off (DAB 2.0 supports OBO for exactly this).
- Where does **`EXECUTE AS`** fit, if at all?
- A **researcher/de-identified** role and a **ward-clerk** (no notes) role to show
  role-scoped predicates, not just provider-scoped.

Deliverable: a short decision + a diagram/table of "who enforces what" (app vs.
engine) so readers know the failure modes of the trusted-subsystem shortcut.

### 2. Keeping embeddings fresh when a source value changes
`clinical.ClinicalNoteEmbeddings` is generated **once** from
`ClinicalNote.NoteText`. If a note is edited (or a field that feeds a derived
embedding source changes), the stored vector goes **stale** — vector search then
retrieves on out-of-date content. (Note: the assistance proc embeds the case
summary *on the fly*, so the query side is fresh; it's the **stored corpus** that
drifts.)

**The question:** what's the right freshness strategy? Evaluate and recommend:
- **Content hash column** (e.g. `HASHBYTES` over the source text) + a periodic
  batch that re-embeds rows whose hash changed. Cheap, idempotent, no hot-path
  cost.
- **Change Tracking / CDC** driving a re-embed queue (event-driven).
- **Trigger on UPDATE** that marks the embedding row dirty (or nulls it) so a
  worker re-embeds — weigh the OLTP hot-path cost of embedding in a trigger
  (don't call the model inline).
- **Recompute cadence** vs. real-time: how stale is acceptable for retrieval?
- Cost angle: re-embedding only changed rows vs. full rebuild (ties to the
  embedding-economics teaching point in Ch 5).

Deliverable: a recommended pattern (likely hash-column + batch worker) with the
"why not a trigger that calls the model" caveat.

**Domain reality for Ward General (2026-07-21):** clinical notes are
**append-only** in practice and by law — a signed note is never edited in place;
corrections are added as a new **addendum** note. So the "stale embedding after an
UPDATE" case that plagues generic corpora largely **does not apply** here. The only
freshness path is **insert**: a new note → a new embedding → the **updateable
DiskANN vector index maintains itself** (full DML, real-time). Framing for the AI
slide: *"embeddings stay fresh because notes are append-only — no edit-in-place to
invalidate; new notes just get new embeddings and the index absorbs the insert."*
- **Book (Ch 5/7):** demo the insert path live — insert a note + embedding, show
  it's immediately retrievable via the updateable index. **Not** demoed in the
  hyperscale-developer app; slide talking point only.
- The hash-column / CDC / trigger patterns above remain the answer for *other*
  domains where source rows genuinely mutate — keep them as the general guidance.

## Content & data hygiene

### No real people in synthetic seed data (provider names)
All seed data is meant to be **fully synthetic — no real PHI and no real people**.
But provider (doctor) names can *coincidentally* match real practitioners:
**"Taylor Brooks" is a real eye doctor.** We need to make sure no seeded
`ops.Provider` name maps to an identifiable real clinician.

Also reconcile the two seed sources: the **book examples** intentionally seed the
provider list with **family names (an in-joke set — including the future
daughter-in-law, Claudia)**, but the demo kit's `build/sql/05-seed.sql` may use a
different, auto-generated name set. Decide on ONE approach and apply it
consistently.

Actions:
- **[DONE 2026-07-21] Kit seed fixed (option B).** Only the *named* cast is
  deliberately fictional (Seinfeld characters + the Ward family, incl. Claudia);
  the risk was the *generated* filler = 20 given names × 20 **real** surnames
  (that cross-product produced "Taylor Brooks"). Swapped the surname pool in
  `build/sql/05-seed.sql` to invented surnames (`Winterbourne`, `Ashdown`, …) so
  no first+last combo maps to a findable real clinician, and added a convention
  note in the script header so it isn't reintroduced.
- **[DONE 2026-07-21] Book seed reconciled.** Applied the same option-B fix to
  `hyperscalebook/examples/ch02-getting-started/05-seed.sql` (invented filler
  surnames + convention note); kit and book now match. Also **weighted the Ward
  family** onto ~10 active encounters each (in their own department) in both seed
  files so the namesake family actually appears on the unit board / charts.
- **[DONE 2026-07-21] Live demo DB patched.** In-place renamed the 116 generated
  providers on the running `wardgeneral` (replaced the real surname of each
  generated name via a positional map; preserved first names incl. "Quinn") —
  "Taylor Brooks" → "Taylor Ashdown", `StillOldSurname = 0`. The Ward-family
  encounter weighting was already applied live.

Deliverable: a cleaned, reconciled provider-name set (kit + book aligned) with a
header note documenting the convention.

## Not yet built (integration TODOs)

- **[DONE 2026-07-20] "AI assistance" in the Blazor app** —
  `clinical.GenerateClinicalAssistance` is surfaced on the bedside chart as an
  advisory, on-demand card (suggested triage flag + grounded summary + note ids,
  human-in-the-loop). Repo method `GetClinicalAssistanceAsync`; model
  `AssistanceResult`.
- **Student research — a separate nav menu item in the Blazor app.** Add a
  `Research` item to the app's `NavMenu` linking to a read-only page that runs
  `clinical.SearchSimilarNotes` (retrieval-only vector search, NO chat) against
  the **named replica** (its own read-only connection string / `research_reader`
  login). Keeps the lower-risk, defensible AI use (retrieval, human reads the
  notes) visibly separate from the clinician's bedside assistance, and shows the
  read-scale-out story (research load never touches the OLTP primary).
  **[REPLICA READY 2026-07-21]** the serverless named replica `wardgeneral-research`
  (HS_S_Gen5_8, 1→8 vCores) is now LIVE on `collierhealth-17`; connection string
  `Server=collierhealth-17.database.windows.net; Database=wardgeneral-research`.
  `clinical.SearchSimilarNotes` + `research_reader` already exist on the primary
  (08-research-vector-search.sql), so they're visible on the replica.
  **[DONE 2026-07-21] Research page built + verified.** `/research` page
  (`Components/Pages/Research.razor`) with a `Research` nav item (search-glyph
  icon), retrieval-only vector search, ranked notes + similarity. Wired via
  `ResearchRepository.SearchSimilarNotesAsync` → `clinical.SearchSimilarNotes` on
  the **named replica** through `WardGeneralConnectionFactory.CreateResearch()`
  (`Research:Database=wardgeneral-research` in appsettings; embed-on-replica proven,
  ~4s). **No student-login isolation** — reuses the app managed identity (Bob's
  call, 2026-07-21); the same SESSION_CONTEXT/RLS trusted-subsystem pattern *could*
  scope a de-identified "researcher" role later (README talking point, not built).
- **DAB** — **[DONE 2026-07-21]** Data API Builder (CLI 2.0.9, `dotnet tool
  install -g Microsoft.DataApiBuilder`) fronts all 13 `clinical.*` procs as REST
  (`/api`) + GraphQL (`/graphql`) + MCP tools, running LOCALLY for the talk
  (`build/dab/run-dab.ps1`; ACA/App Service on the arch slide). Passwordless via
  `DAB_CONNECTION_STRING` (Active Directory Default). **Key finding (Learn-verified):
  DAB does NOT support the SQL 2025 native `json`/`vector` types** (Feature
  availability → Unsupported data types) — it aborts introspecting any proc with a
  json/vector param OR result column. FIX (app procs untouched): dropped the unused
  `@QueryVector` from `SearchSimilarNotes`; added `build/sql/11-dab-adapters.sql` =
  4 thin boundary adapters (`GetPatientChartApi`/`ByBedApi` CAST 11 json cols→text;
  `AdmitPatientApi`/`FileLabResultApi` accept json-as-nvarchar). Also: DAB rejects
  `//comment` keys (only root `//`); `null` param defaults coerce to `""` (omit the
  block). VERIFIED live: REST 40k encounters, chart 249 (Art Vandelay), vector
  search 3 notes. Teaching point = engine ahead of tooling; serialize at the boundary.
- **MCP server** — **[DONE 2026-07-21]** DAB's MCP endpoint (`http://localhost:5000/mcp`)
  wired into VS Code via `.vscode/mcp.json` (server `wardgeneral-dab`). Verified 20
  tools (7 generic DML + 13 proc custom-tools) via a JSON-RPC initialize→tools/list
  probe (`build/dab/probe-mcp.ps1`). **Stage safety:** the 8 write procs are locked
  (`custom-tool:false` + `authenticated` role) so the anonymous demo is read-only
  (12 tools, writes 403) — flip back for a live-write demo. Demo runbook + prompts
  in `DEMO-RUNBOOK.md`. Book vision (not built): expand the agent to Microsoft Agent
  Framework and/or Foundry Agent (README/slide talking point).  **Book follow-up (name):** the VS Code picker shows **"SQL MCP Server"** — proven
  to be DAB's hardcoded `serverInfo.name` (v2.0.9); VS Code shows that, not the
  mcp.json key. `runtime.mcp` has no `name` field (only `description`, which we
  branded as the initialize `instructions`). *Live with it for the talk.* To
  actually control the label, try **stdio transport** (`dab start --mcp-stdio` from
  mcp.json — VS Code manages the process, label follows the config ID). Untested.