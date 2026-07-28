# Session handoff — SQL MCP Server talk

> **Purpose:** Pick this work up on another computer. This captures *where we are*, *what's decided*,
> *what's verified*, and *what's next*. Last updated **2026-07-26**.

---

## ⭐ LATEST STATE (2026-07-26) — read this first (sections below are earlier context)

**Environment (all LOCAL):** SQL Server 2025 **default instance `localhost`, Windows integrated auth**
(no container, no sa). DAB self-hosted as an **HTTP** server on **:5001** (stdio is a documented alternate).
Kit is **location-independent** (`$PSScriptRoot` + `localhost`); repo cloned to the **same path `c:\bwsql`** on
every machine.

**Build / run (the scripts):**
- `build/setup.ps1` — one-shot build (prereq check → download → restore AdventureWorks → deploy view → `dab validate`).
- `build/start-mcp-http.ps1` — go live: verify + start DAB HTTP :5001 + prove MCP `initialize` → **"GO LIVE: GREEN"**. `-Stop` / `-Restart`. **After any config edit, use `-Restart`** (plain run reuses a stale process).
- `build/verify-preflight.ps1` — read-only checks (504 products, view=14, dab≥2.0.9, `dab validate`, ≤1 DAB proc).
- `demos/mcp-call.ps1 <tool> [-Arguments @{...}]` — session-aware MCP `tools/call` over :5001 (rehearsal helper).
- Skills: **build-sqlmcpserver-demo** ("Build the sqlmcpserver demo environment on this machine") and **run-sqlmcpserver-demos** ("let's start the SQL MCP Server demos").

**Config — `build/dab/dab-config.json` now has 13 entities (validated + live):**
- 9 **read-only tables**: Products, ProductCategories, ProductSubcategories, ProductModels, SalesOrders
  (Sales.SalesOrderHeader), SalesOrderDetails, Customers, SalesPeople, SalesTerritories.
- 1 **view**: `ProductComponents` (`mcp.vProductComponents`) — **REST off**, GraphQL + MCP default on; has a
  `fields` block in the baseline (the 9 tables + 3 procs do not → `dab validate` warns "missing fields" on 12 entities).
- 3 **stored-proc entities via generic `execute_entity`** (NO custom-tool, Bob's choice): GetWhereUsedProductID
  (default StartProductID=948, CheckDate '2013-05-30'), GetManagerEmployees (BusinessEntityID=2), GetEmployeeManagers (=9).
- `uspGetBillOfMaterials` is **reserved for Demo 4** (live add-a-tool). Not exposed: uspLogError/uspPrintError,
  uspSearchCandidateResumes, HumanResources.uspUpdate* (write), CreditCard/PersonCreditCard/EmployeePayHistory.

**Demos:** 1 Cold open ✅ verified (14). 2 "One config: show/validate/query" ✅ (config reveal · `dab --version`/`--help`/`validate`
→ 12 "missing fields" warnings → **live fix**: `reset-dab-config.ps1 -ApplyFields` (pre-built, instant, 12 → **0**
warnings incl. procs) · GraphQL Nitro → 14). 3 Under the hood (XE `demos/demo3-xe-capture.sql`) ✅ **verified 2026-07-26**:
session captured 0 rows before the read (describe_entities = no SQL), then one `rpc_completed` = `exec sp_executesql`
`... FROM [mcp].[vProductComponents] WHERE [ProductModel] = @param1` with `@param1 nvarchar(12)` (= "Touring-1000",
bound, not concatenated). NOTE: running the .sql file itself also matches the `%ProductComponents%` filter (word is in
comments) → a stray `sql_batch_completed`; driving the tools from the AGENT avoids it. Optional: tighten filter to
`rpc_completed` only. 4 Add-a-tool live ✅ **built + verified 2026-07-26** (see DEMO 4 block below).

**DEMO 4 — built + verified 2026-07-26:** Custom tool `get_product_bom` over `dbo.uspGetProductBOM`
(`build/sql/02-demo4-bom-proc.sql`, deployed by `setup.ps1` step 3b). Proc keyed by MODEL name → resolves a
representative ProductID → returns the **full recursive BOM**. **Gotcha (root-caused):** the recursive CTE is
**INLINED**, not `EXEC dbo.uspGetBillOfMaterials` — a nested `EXEC` returns NULL from
`sys.dm_exec_describe_first_result_set`, so DAB can't build the entity and `dab validate` reports "Config is
invalid." Inlining makes the final `SELECT` describable. Committed config `dab/dab-config.tool.json` = the FULL
final state = `fields.json` (all 9 tables + 3 procs described, **0 warnings**) + the `GetProductBOM` entity
(`mcp: { custom-tool: true }`, descriptive `parameters` array, string default "Touring-1000", its own `fields`
block) + a **tuned `ProductComponents` (view) description** (now "quick FLAT top-level list" instead of
"complete parts list") so the SAME cold-open prompt escalates to the tool. Self-contained switch — the proc is
already in the DB from build (setup.ps1 3b), no live editing. Deterministic apply: `reset-dab-config.ps1
-ApplyTool` (validates + restarts DAB); reset with plain `reset-dab-config.ps1`. **Verified once** (2026-07-26):
tool advertises as `get_product_bom` and returns **87 rows, BOMLevel up to 4** for Touring-1000. Payoff: view = 14
top-level parts; tool = 87-row, 4-level recursive assembly. **Live behavior (2026-07-26, worked great):** with the
SAME cold-open prompt "What parts make up the Touring-1000 bike?", the agent returned the view's flat 14 FIRST,
then proactively OFFERED a deeper breakdown and called `get_product_bom` for the 87-row recursive BOM — a nicer
two-step than a hard swap. **`dab validate` false-negative lesson:** it needs
`$env:DAB_CONNECTION_STRING` set in the shell; unset → "Config is invalid" for ANY config (even baseline) — not
a config bug. All reset/start scripts set it; a bare shell does not.

**DEMO 3 TOOLING — finalized 2026-07-26:** Two panes = **Chat Debug view** (`/debug`; System prompt shows the MCP
server description that routes, Tool responses show `describe_entities`/`read_records` payloads) + **XE via SSMS
Watch Live Data**. Pre-flight `build/start-xe-capture.ps1` (creates+starts `dab_mcp_capture`, idempotent) BEFORE the
cold open; teardown `-Stop`. Verified live: `read_records` emits `exec sp_executesql … FROM [mcp].[vProductComponents]
WHERE ([ProductModel]=@param0)`, `@param0` bound = "Touring-1000"; `describe_entities` emits no SQL. **Agent Debug Log**
panel (VS Code preview, setting `github.copilot.chat.agentDebugLog.fileLogging.enabled`) was tried and DROPPED — thin
on this build; setting removed from user settings.json. DAB `--LogLevel Debug` + logging proxy considered, NOT needed.

**FIELDS / WARNINGS — settled 2026-07-26 (verified on DAB 2.0.9):** The `missing 'fields'` warning fires for
**every** MCP-enabled entity without a top-level `fields` array — tables, views, AND stored procs. For a proc
the fix is a `fields` block listing its **result-set columns** (from `sys.dm_exec_describe_first_result_set`);
adding proc **`parameters`** does NOT clear the warning. A `fields` block on a proc is additive metadata only —
it does not project/restrict the result set (verified: `GetManagerEmployees` still returns all 7 columns).
`dab-config.fields.json` now describes all 9 tables + 3 procs → `dab validate` **0 warnings**. Two states:
`dab-config.json` = 12-warnings baseline (Demo 2 "before"); `dab-config.fields.json` = 0-warnings "after",
applied via `reset-dab-config.ps1 -ApplyFields`.

**PROC PARAMETERS — added 2026-07-26:** `source.parameters` has two shapes: the **map** form `{ "name": value }`
(sets a default value only, no description) and the **array** form `[ { name, description, required, default } ]`
(adds the description the model reads via `describe_entities`). They're mutually exclusive. `dab validate` does
**NOT** flag missing parameter descriptions (only missing `fields`), so the input side is on us. `dab-config.fields.json`
now uses the array form on all 3 procs with input descriptions; defaults are **strings** (`"948"`, `"2"`, `"9"`) —
an int default fails schema validation. Verified defaults still execute via empty-body REST: GetManagerEmployees=13,
GetEmployeeManagers=3, GetWhereUsedProductID=97 rows. `GetEmployeeManagers` default changed **2 → 9** (id 2 = Terri
Duffy, near the org top, returned 0 rows; id 9 returns a 3-row chain) — updated in BOTH baseline (map form) and
fields (array form).

**KEY ARCH INSIGHT (added to all 3 DAB diagrams):** "describe_entities does no SQL" = no SQL *per request*. DAB
reads the schema **once at startup** and caches it (that's how it builds valid parameterized SQL). Two in-memory
stores: **config** (drives describe_entities → so tables w/o a `fields` block show 0 fields to the model) and
**boot-cached schema** (drives read_records/execute). The cache serves DAB; `fields` serves the model.

**Security (narrate; nothing built):** DAB connects as **sysadmin** (Windows auth) → the **config is the only gate**;
least-privilege connection = defense in depth. `permissions` = **DAB RBAC**, independent of SQL GRANTs, checked
**before SQL**. `set-session-context: false` (RLS off — no per-user claims). "Look what we *didn't* expose"
(CreditCard). Connection string via `@env('DAB_CONNECTION_STRING')` set by the scripts at **DAB startup**.

**Diagrams (`diagrams/`):** mcp-before, mcp-after, dab-overview, sqlmcpserver (navy request-path), sqlmcp_flow
(light), sqlmcp_tools (navy), sqlmcp_bestpractices (light).

### WHAT'S NEXT
1. **Demo 4 decision** — Option A: purpose-built `dbo.uspGetProductBOM @ProductModel` (1 clean param, matches
   cold open; recommended) vs Option B: stock `uspGetBillOfMaterials` + a `Products` entity so the agent resolves
   model→ProductID. Then wire it as a `custom-tool` (`get_product_bom`) live.
2. **Rehearse Demo 3** (XE capture — describe_entities = no events, read_records = one bound `@param0`).
3. Optional decisions (all narrate-only unless chosen): add `fields` to the tables, entity `cache.enabled`,
   the RBAC role-flip beat, least-privilege connection.
4. Security wrap slide.

> **Cross-laptop:** `/memories/repo/sqlmcpserver-t12.md` is **local to this machine** and won't travel — this
> committed SESSION.md + `demo-runbook.md` are the source of truth. **Commit + push before switching laptops.**

---

## Where we are

Building the session **"SQL MCP Server: Bringing AI Agents to Your SQL Data"**
(Bob Ward, Microsoft · Visual Studio Live! HQ 2026 · Tue 07/28/2026, 1:30–2:45pm · Intermediate · 75 min).

**Two docs are complete and factually aligned:**

- [outline.md](outline.md) — the working session outline (5-part teaching arc, timing, demo inventory,
  pre-flight checklist, open questions).
- [README.md](README.md) — talk overview, local-vs-Azure mapping, Ward General scenario, the "two tool
  families" governance story, and a **"SQL MCP Server facts (verified)"** reference table.

---

## The decision that shaped everything

**Everything runs LOCAL — no cloud egress.**

| Layer | This talk (local) | (Was, in hyperscale-developer kit) |
|-------|-------------------|-------------------------------------|
| Database | **SQL Server 2025** — local **Windows** instance, `localhost`, **Windows (Integrated) auth**, **stock AdventureWorks2022** | Azure SQL Hyperscale, Entra passwordless |
| MCP server | **Data API builder** (`dab`) local, `http://localhost:5001/mcp` | same DAB, Azure-pointed |
| Agent | VS Code Copilot agent (local) | same |
| RBAC demo | **DAB Simulator** provider (dev-only, `X-MS-API-ROLE` / `role:<name>`) | Entra roles |
| Optional RAG | Foundry Local (phi-4 + qwen3-embedding) | Azure OpenAI |

---

## The one message (thesis)

> **You already know how to do this.** Exposing data to an AI agent safely is the same job you've always
> done — least privilege, stored procedures, views, GRANT/REVOKE, Row-Level Security — only the *consumer*
> is now an agent. The **SQL MCP Server (DAB)** is the governed bridge.

Scenario: **Adventure Works** — the stock `AdventureWorks2022` sample DB. A sales-ops analyst's Copilot
agent queries products, bills of materials, orders, and sales reps through a governed SQL MCP Server
surface. **Ward General was dropped** (it's used in the co-located hyperscale talk); AdventureWorks is
simpler, universally known, and keeps 100% of attention on MCP/DAB/governance.

---

## Verified facts (ground truth — re-check before the talk, DAB moves fast)

Sourced from `aka.ms/sql/mcp` → [learn.microsoft.com/azure/data-api-builder/mcp](https://learn.microsoft.com/en-us/azure/data-api-builder/mcp/)
and `.../mcp/data-manipulation-language-tools`. Verified **2026-07-23/24**.

1. **SQL MCP Server *is* Data API builder.** Learn landing page: *"SQL MCP Server is built on Data API
   builder."* There is **no separate "MSSQL MCP Server" product.** The genuinely separate SQL tool is the
   **MSSQL VS Code extension** (dev-time DDL companion). SQL MCP Server is **data-plane only, no DDL** by design.
2. **Open source, MIT, always free.** Repo [github.com/Azure/data-api-builder](https://github.com/Azure/data-api-builder)
   (MIT license). README: *"Data API builder (DAB) is open source and always free."* Latest release **2.0.9**
   (~3 weeks ago). MCP ships in that same repo (topics `mcp` / `mcp-server`).
3. **Two tool families:**
   - **Built-in DML tools (7), ON by default** when MCP enabled: `describe_entities`, `read_records`,
     `create_record`, `update_record`, `delete_record`, `execute_entity`, `aggregate_records`
     (`aggregate_records` is 2.0+). `read_records` = single table/view, **no JOINs** (use a view or proc).
   - **Custom tools** via `mcp.custom-tool: true` on **stored-procedure entities** → named tools.
4. **No NL2SQL — it's "NL2DAB."** The DAB Query Builder emits **deterministic** T-SQL from structured tool
   args. No free-form model SQL, ever.
5. **Governance = narrow the default surface:** global per-tool toggles (`runtime.mcp.dml-tools.<tool>: false`),
   per-entity (`mcp.dml-tools: false`), and **RBAC** (role → action → field include/exclude) + policies + **RLS**,
   applied identically across REST / GraphQL / MCP. Disabling `custom-tool` only removes the *named* tool — the
   proc is still callable via generic `execute_entity` unless disabled or the role lacks `execute`.
6. **Availability:** MCP on by default in **DAB 1.7+**; use **2.0+** for latest.
7. **Transports:** streamable **HTTP** (`/mcp`) + **stdio** (`dab start --mcp-stdio [role:<name>]`).
   MCP protocol version **2025-06-18**.
8. **Ops:** L1/L2 caching on `read_records`, OpenTelemetry spans per tool call, health checks, App Insights.
9. **Inspect:** `npx -y @modelcontextprotocol/inspector http://localhost:5001/mcp`.

**Canonical docs (use these, NOT the old 404 `/concept/model-context-protocol`):**
- Overview: `https://learn.microsoft.com/azure/data-api-builder/mcp/`
- DML tools: `https://learn.microsoft.com/azure/data-api-builder/mcp/data-manipulation-language-tools`
- Repo: `https://github.com/Azure/data-api-builder`

---

## Reusable assets (patterns only — config + SQL are authored fresh for AdventureWorks)

`c:\bwsql\presentations\hyperscale-developer\build\` supplies **script scaffolding** to adapt:
- `dab/run-dab.ps1`, `dab/setup-dab.ps1` (adapt: local SQL auth + Simulator provider)
- `dab/probe-*.ps1` (server info / tool descriptions / tool call — reuse as-is)

**New for this talk (not a re-point of the clinical kit):**
- **Restore stock `AdventureWorks2022`** into the container (no schema/seed authoring).
- **`dab/dab-config.json`** — authored fresh: AdventureWorks entities (`uspGetBillOfMaterials`,
  `uspGetManagerEmployees`, `uspGetWhereUsedProductID` as `custom-tool`s; order + sales-rep views for
  the DML tools), MCP toggles, and `SalesReader` role permissions.
- **`sql/10-row-level-security.sql`** — authored fresh: `SECURITY POLICY` on `Sales.SalesOrderHeader`
  by `SalesPersonID` (the only DDL we add).
- *(buffer)* embeddings over `Production.ProductDescription` for `SearchSimilarProducts` (Foundry Local).

---

## Next actions (in order)

1. **Build the deck** from [outline.md](outline.md) — the scenario + demo flow are now locked (AdventureWorks).
2. **Scaffold the local `build/` kit:** SQL Server 2025 `docker-compose`, restore stock `AdventureWorks2022`,
   author `dab-config.json` (AdventureWorks entities + Simulator provider + `SalesReader` role), and the
   RLS `SECURITY POLICY` (`sql/10`).
3. **Rehearse** cold open (`GetBillOfMaterials`, no SQL), RBAC flip (`SalesReader`), RLS (`SalesPersonID`).

## Decisions (locked 2026-07-24)

- **Scenario:** full **AdventureWorks2022** (OLTP), restored stock — replaces Ward General.
- **DB stays stock** — zero authored procs; custom tools use AdventureWorks' native procs. Only DDL = the
  RLS `SECURITY POLICY` (which *is* the RLS demo).
- **Cold open:** custom tool `GetBillOfMaterials` → *"What parts make up the Touring-1000 bike?"*
- **RBAC:** DAB Simulator, role `SalesReader` flipped via `X-MS-API-ROLE`.
- **RLS:** main flow, `SalesPersonID` on `Sales.SalesOrderHeader`.
- **Vector-RAG:** buffer only (`SearchSimilarProducts` over `Production.ProductDescription`).
- **Local auth:** `sa`/SQL auth, dev-only (prod = managed identity).

**Still open:**
- Build-kit shape: dedicated local `build/` here (leaning yes) vs. container override on an existing kit.

---

## Quick start on the other machine

1. Open the `bwsql` workspace in VS Code.
2. Read [SESSION.md](SESSION.md) (this file) → [outline.md](outline.md) → [README.md](README.md).
3. Resume at **"Next actions"** step 1: review the outline.
