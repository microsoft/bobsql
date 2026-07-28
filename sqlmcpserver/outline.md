# Outline — SQL MCP Server: Bringing AI Agents to Your SQL Data

**Event:** Visual Studio Live! — Microsoft HQ 2026 · Tuesday 07/28/2026 · 1:30–2:45pm
**Length:** 75 min = **~62 min content + ~13 min Q&A** (see timing cuts)
**Level:** Intermediate · **Audience:** developers + DBAs who own SQL and are being asked to "add AI"
**Style:** Demo-heavy. Slides are connective tissue. Majority of runtime is **VS Code + a live SQL MCP Server** on screen.
**Everything is LOCAL** — SQL Server 2025 container + DAB + Copilot agent. No cloud egress required.

---

## The one message

> **You already know how to do this.** Exposing data to an AI agent safely is the same job you've
> always done — least privilege, stored procedures, views, GRANT/REVOKE, Row-Level Security — only the
> *consumer* is now an agent instead of an app. The **SQL MCP Server** (DAB) is the governed bridge
> that makes your existing SQL skills the thing that puts AI to work — safely.

The talk is a **five-part teaching arc**, each part earning the next:

| # | Section | The question it answers | Proven live |
|---|---------|-------------------------|-------------|
| **1** | **What is MCP, and why** (+ the Microsoft MCP landscape) | Why do agents need a protocol at all? Where does SQL fit? | Cold open — agent answers a Touring-1000 parts question via a tool, no SQL written |
| **2** | **What is DAB, and why** | What turns SQL objects into an API without middle-tier code? | DAB running local: same procs as REST + GraphQL + MCP |
| **3** | **How to enable MCP with DAB** | What actually makes it a SQL MCP Server? | The `runtime.mcp` block + `custom-tool` in `dab-config.json`; wire `.vscode/mcp.json` |
| **4** | **How the SQL MCP Server works** (under the hood + security) | How does a proc become a typed tool, safely? | Request path; RBAC role-flip; stored-proc-only; RLS in the engine |
| **5** | **Using it in practice for AI agents** | What does this look like day to day — and in production? | Copilot agent flow; add a tool live; same config → Azure SQL / Fabric |

---

## Runtime outline (75-min cut)

### 1 — What is MCP, and why? (0:00–0:12)
*Includes the Microsoft MCP landscape. Answers "why a protocol," then "where SQL fits."*

**Cold open (~4 min) — no title slide.**
- Open **directly in VS Code**, Copilot **agent mode**, connected to the **local** SQL MCP Server.
- Ask in plain English: *"What parts make up the Touring-1000 bike?"*
- The agent makes two MCP calls — **`describe_entities`** (discovers the `ProductComponents` entity) then **`read_records`** with a typed OData filter `ProductModel eq 'Touring-1000'` — and returns the **14-part** list in seconds. **The model wrote no SQL.** *(Verified live 2026-07-24.)*
- Expand the tool call: **tool name, typed arguments (`entity` + `filter`), JSON result.** The model emitted a *typed, validated filter* — never SQL; DAB compiled it to **one parameterized query against a view I control**.
- **The line:** *"That agent never wrote a line of SQL. It asked one question; the server ran one set-based query against a view I own, under permissions I control — all on this laptop. Same skills you already have: a view, a filter, least privilege — only the caller is an agent now. To see why that's the right way, start with the protocol."*

**Why MCP (~4 min) — slides.**
- **The trap:** the naive path is handing an LLM a connection string and hoping the prompt says "please don't drop the table." That's not a security model — it's an incident waiting to happen.
- **What MCP is:** the **Model Context Protocol** — an open, client/server standard for how AI apps (hosts) discover and call **tools** and read **context**, consistently, instead of every integration being bespoke. Hosts (Copilot, IDEs) ↔ clients ↔ **MCP servers** that expose tools.
- **Why it matters for data:** a tool is a *typed, named, described, permissioned* capability — not a raw query surface. That's exactly the shape a DBA wants around a database.

**The Microsoft MCP landscape (~4 min) — one slide, `github.com/microsoft/mcp`.**
- Microsoft already ships a broad catalog of first-party MCP servers — position SQL as *one governed member of a large, official family*:
  - **Cloud & infra:** Azure MCP, Azure Resource Manager, AKS, Microsoft Foundry
  - **Data & analytics:** **Microsoft SQL (MSSQL) MCP**, Microsoft Fabric + Fabric Real-Time Intelligence, Dataverse
  - **Dev tools:** GitHub, Azure DevOps, Playwright, NuGet, Dev Box
  - **Productivity / M365 / security:** Microsoft Learn, M365 Copilot/Mail/Teams, Enterprise (Graph), Sentinel
- **The SQL angle — clear up a naming point:** the catalog's **"Microsoft SQL"** entry (`aka.ms/sql/mcp`) **is** the **SQL MCP Server built on Data API Builder** — that's today's topic, *not* a separate product. The genuinely separate SQL tool is the **MSSQL extension for VS Code**, a *dev-time* companion for schema / **DDL** work — SQL MCP Server is deliberately **data plane only (no DDL)**. Position: **SQL MCP Server = governed production data access; MSSQL extension = local schema editing.**
- **Transition:** *"It's built on DAB. So — what is DAB, and why does it belong in this story?"*

### 2 — What is DAB, and why? (0:12–0:22)
*Answers "what turns SQL objects into an API — with no middle-tier code."*

- **What DAB is (~3 min) — slide + repo:** **Data API Builder** — Microsoft's **open-source**, **config-driven** engine that exposes your database objects (**tables, views, stored procedures**) as **REST** and **GraphQL** — and now **MCP** — with **no middle-tier code**. Works across SQL Server, Azure SQL, **Fabric SQL Database**, PostgreSQL, MySQL, Cosmos DB.
- **Why DAB, for a DBA (~3 min):** the value props are *your* values — **RBAC per entity/action**, **stored-procedure-fronted** access, parameterized execution (no string-built SQL), a single reviewable **config file in source control**. "It's the API layer you'd have hand-built — as configuration."
- **See it run, local (~4 min):**
  - Local **SQL Server 2025** instance (`localhost`, Windows auth); MSSQL extension shows the stock **AdventureWorks** schemas (`Sales`, `Production`, `HumanResources`, `Person`, `Purchasing`) + the **stored procedures and views that already ship with it** — nothing we added.
  - Start DAB (`build.ps1`, HTTP mode on `localhost:5001`). **`/api` (REST)** and **`/graphql`** light up. Hit the same entity both ways. "Same object. Two surfaces. Zero middle-tier code." *(The MCP surface itself runs over **stdio** — VS Code manages it — but REST/GraphQL prove the 'three surfaces, one config' point here.)*
- **Transition:** *"Two surfaces so far. The third — the one this talk is about — is MCP. Here's how you turn it on."*

### 3 — How to enable MCP with DAB (0:22–0:34)
*Answers "what actually makes this a SQL MCP Server." The config walkthrough — and the key surprise: it's mostly ON already.*

- **It's on by default (~2 min):** in DAB 1.7+/2.0, if you already have a working DAB config, **MCP is enabled automatically** — entities participate unless you restrict them. The **`runtime.mcp`** block (`enabled`, `path: "/mcp"`, `description`) is where you *narrow* it, not switch it on. Restart DAB → **`/mcp` serves alongside `/api` and `/graphql`.**
- **Two families of tools (~4 min) — the thing to understand:**
  - **Seven built-in DML tools**, auto-generated across every MCP-enabled entity: `describe_entities`, `read_records`, `create_record`, `update_record`, `delete_record`, `execute_entity`, `aggregate_records`. A **typed CRUD surface** — the agent discovers entities, then reads/writes through structured parameters (OData-style filters), **not SQL**. Design principle: **no NL2SQL — "NL2DAB"**, DAB builds deterministic T-SQL. (Strong safety line.)
  - **Custom tools** — layered on top: mark a stored-procedure entity `mcp: { "custom-tool": true }` to register it as a **named, described** tool (e.g. `get_product_bom` over an authored `dbo.uspGetProductBOM`) the agent picks by name. Walk the entity: `source` (the proc) + typed params → the tool's **argument schema**; `description` → the *when-to-call* contract. Custom tools are also how you expose capabilities the SQL MCP Server has **no built-in tool** for — e.g. a **vector / semantic search** over embeddings: wrap it in a proc and publish it as a custom tool.
  - **Honest nuance to say out loud:** the cold open used a **built-in DML tool** (`read_records`), so the model emitted a typed, validated **OData filter** (`ProductModel eq 'Touring-1000'`) — never SQL — which DAB compiled to **one parameterized query against a view**. A **custom tool** (a named stored proc) is the other family: the model emits *nothing but proc parameters*. Neither lets the model author SQL. (We deliberately chose the DML-tool + view opener so it's **one question → one set-based query** — the "beauty of SQL" honored, not a chatty multi-call orchestration.)
- **Narrow the surface (~4 min) — this is the governance story:** since DML tools are on by default, *enabling* isn't the interesting part — *constraining* is. Show the levers:
  - global per-tool toggles (`runtime.mcp.dml-tools.delete-record: false` kills deletes everywhere),
  - per-entity (`mcp: { "dml-tools": false }` so an entity is reachable only via its blessed custom tool),
  - **RBAC** permissions per role / action / field.
  "Default gives you a governed CRUD surface; you dial it down to exactly what you bless."
- **Wire it to the agent (~2 min):** `.vscode/mcp.json` → **`Adventure Works (SQL MCP)`** as a **stdio** server (`dab start --mcp-stdio role:anonymous --config …`) — VS Code launches and manages the process. **MCP: List Servers** → start → the tool list appears. Or inspect it: `npx -y @modelcontextprotocol/inspector`.
- **How the agent knows it's *your* database (~2 min) — the question every attendee asks:** the DML tools (`read_records`, `aggregate_records`) are database-**agnostic verbs**; the "this is Adventure Works" knowledge lives in **metadata**, in two places: (1) the server-level **`runtime.mcp.description`** → delivered as the MCP **instructions** at connect; (2) the per-**entity**/per-**field** `description` → returned by **`describe_entities`**. The agent's routing is: read the descriptions → pick the entity whose description matches the ask → call the generic verb with that `entity` + an OData `filter`. DAB then builds the deterministic, parameterized T-SQL. **Your descriptions are the routing layer** — weak descriptions = the agent guessing column names.
- **Transition:** *"That's the surface. Now open the hood — what happens on a tool call, and why it's safe."*

### 4 — How the SQL MCP Server works (0:34–0:50)
*Under the hood + "the security controls you already care about." The technical + trust heart.*

- **The request path (~4 min):** trace one call — `agent → MCP tool invocation (JSON args) → DAB validates args + role + policy → DAB builds deterministic T-SQL / binds proc params → SQL returns rows → DAB shapes JSON → agent`. The design principle: **NL2DAB, not NL2SQL** — the model never emits SQL; DAB's Query Builder generates it deterministically from structured tool arguments; parameters are **bound, never concatenated**. Destructive actions aren't blocked by "no tool exists" — they're blocked by **RBAC + per-tool toggles** you set (show `delete-record` disabled, or a role without `delete`).
- **RBAC, live (~5 min):** switch DAB's dev host to the **Simulator** auth provider (dev-only) so roles set via the `X-MS-API-ROLE` header can be demoed offline.
  - Tool call as `SalesReader` → works. Remove `SalesReader`'s `execute` (or change the sent role) → re-ask → **rejected at DAB, before SQL.** "Authorization lives in the bridge, per entity, per action — GRANT/REVOKE you already know, one layer up."
- **Constrain the surface, live (~3 min):** by default the built-in DML tools give the agent a typed CRUD surface over MCP-enabled entities. Lock it down: set the sensitive entities to `mcp: { "dml-tools": false }` and/or disable `create/update/delete-record` globally, leaving only `read_records` + your blessed **custom-tool** procedures. Re-list tools → the surface shrinks to exactly what you allow. "Governed by config + RBAC — reachable only through what I published."
- **Row-Level Security in the engine (~3 min, narrate):** a `SECURITY POLICY` on `Sales.SalesOrderHeader` scoped by **`SalesPersonID`** would filter orders to the acting rep — RLS runs in the **engine**, so it applies no matter which tool calls. "Defense in depth — the bridge *and* the engine." (Described, not a built live beat.)
- **The sensitive thing you don't expose (~1 min):** `HumanResources.EmployeePayHistory` / `Rate` is simply **not** published as an entity — and even if `execute_entity` reached that far, no role the agent holds can touch it. "Least privilege isn't a switch you flip; it's the surface you chose to publish."
- **Least privilege + audit (~1 min):** DAB's own login is least-privileged (read/execute on the published objects only); every call is an auditable parameterized execution (XEvents/Audit). "Your security, applied to a new consumer."
- **Land it:** *"RBAC, stored procedures, RLS, least privilege — the agent is just another caller, subject to all of it."*

### 5 — Using it in practice for AI agents (0:50–1:00)
*Answers "what does this look like day to day — and in production?"*

- **The agent flow (~3 min):** back in Copilot agent mode, a realistic multi-step ask (*"which components of the Touring-1000 are used in other products too?"*) — the agent **chains tools** (`get_product_bom` → `GetWhereUsedProductID`) and reasons over structured results. "It's composing your tools, not improvising SQL."
- **Add a tool live (~4 min):** take an existing stock proc not yet exposed (e.g. `dbo.uspGetManagerEmployees` or `dbo.uspGetWhereUsedProductID`) → add a small entity with a good `description` + `custom-tool: true` + read permission → restart DAB → **the agent discovers and uses the new tool.** "Publishing an AI capability was: write a description, set a permission. A reviewable config change — and I never touched the database."
- **Run it anywhere (~3 min):** going to production changes **two things** — the **connection string** (container → **Azure SQL** or **Fabric SQL Database**) and the **auth provider** (`Simulator` → **Entra / managed identity**); DAB moves to **Azure Container Apps**. **Entities, tools, descriptions, permissions, T-SQL: byte-for-byte the same.** "Learn it on your laptop; ship the same config to the cloud."

### Wrap + close (1:00–1:02)
- **Recap the arc** over one diagram: agent → **MCP** → **DAB (SQL MCP Server)** → **stored procs + RLS** → engine. Five questions, answered live.
- **Close line:** *"Everyone wants AI to talk to your data. You're the one who can let it — safely. The SQL MCP Server is how. Go build the bridge."*
- Resources slide: DAB docs + SQL MCP, `github.com/microsoft/mcp`, QR code.

### Q&A (1:02–1:15, 13 min)
- Take questions. **If they run dry, pull from Buffer Material** (below) with the close slide up.

---

## Buffer material (only if time / low Q&A) — all local, all reuse

Pull in this order:
1. **Vector search via a custom tool (fully local):** vector / semantic search is **not** a built-in SQL MCP Server tool — you expose it the same way you'd expose any capability: wrap an embeddings query in a stored proc and publish it as a **custom tool**. Embed `Production.ProductDescription` with **Foundry Local** (phi-4 + qwen3-embedding); agent: *"find products similar to a lightweight aluminum road frame."* Still zero cloud. (~4 min)
2. **REST/GraphQL parity:** hit the **same** entity over `/api` and `/graphql` to prove "same proc, three surfaces." (~2 min)
3. **Probe internals:** `probe-serverinfo.ps1` / `probe-toolcall.ps1` — the raw MCP handshake + a hand-issued tool call. (~2 min)
4. **Write path with role gate:** call a write DML tool (`create_record` / `update_record` on an orders entity) as a role that holds it, then show the agent's role deliberately *lacks* it — the write is rejected at DAB. (~3 min)
5. **Diff to cloud:** show that going to Azure changes only the connection string + auth provider — entities, tools, and T-SQL in `dab-config.json` are identical. (~2 min)

---

## Demo inventory (local)

| # | Demo | Source | Cloud egress? | Risk | Notes |
|---|------|--------|---------------|------|-------|
| 1 | Cold open: agent → `read_records` over `mcp.vProductComponents` (Touring-1000 → 14) | `build/` + `dab-config.json` | **No** | Low | Anchor; view + DML tool; rock-solid offline |
| 2 | One config: show / `dab validate` / GraphQL on `localhost:5001` | `dab-config.json` | **No** | Low | DAB must be up first |
| 3 | Under the hood: XE — `describe_entities` (no SQL) then parameterized `read_records` | `demos/demo3-xe-capture.sql` | **No** | Low | Start the XE session before the prompt |
| 4 | Add a tool live: `get_product_bom` over `dbo.uspGetProductBOM` | `reset-dab-config.ps1 -ApplyTool` | **No** | Med | 87-row recursive BOM; config switch |
| — | Back pocket (narrate only): RBAC role-flip, RLS by `SalesPersonID`, not exposing `EmployeePayHistory`, vector search via a custom tool | — | **No** | — | Not a built live beat |

---

## Pre-flight checklist (day-of)

> The authoritative pre-flight lives in the kit — **not** here. Use these; this
> outline is a planning artifact and predates the current build.
>
> 1. **Automated checks (read-only):** `./build/verify-preflight.ps1` — asserts DB
>    reachable (localhost, **Windows auth**), `Production.Product = 504`,
>    `mcp.vProductComponents` Touring-1000 = **14**, `dab` CLI ≥ 2.0.9, `dab validate`.
>    Exit 0 = all green.
> 2. **One-command go-live:** `./build/start-mcp-http.ps1` — runs the verifier, starts
>    DAB HTTP on **`:5001`** (`/api`, `/graphql`, `/mcp`), and proves the MCP
>    `initialize` handshake → **GO LIVE: GREEN**.
> 3. **Full written run-of-show + pre-flight:** [`demo-runbook.md`](demo-runbook.md) § *Pre-flight (do before the room fills)*.
>
> Room hygiene (still on you): fonts ≥ 18pt in VS Code / terminal / MSSQL extension,
> dark theme, zoom rehearsed, and everything works with **Wi-Fi off**.

---

## Timing cuts

- **60-min cut (~50 content + 10 Q&A):** trim §1's landscape to a single slide (name-drop the catalog, don't tour it); fold §2's REST/GraphQL demo into §3; drop §5's "add a tool live" to a described (not typed) change; keep §4 (RBAC + RLS) intact — it's the point.
- **90-min cut (~75 content + 15 Q&A):** promote **Buffer 1 (vector-search RAG)** and **Buffer 4 (write path/role gate)** into the main flow after §4.

---

## Decisions (as built)

1. **Scenario:** stock **AdventureWorks (`AdventureWorks2022`, OLTP)**, restored unmodified.
2. **Read-only config, 13 entities:** 9 tables + the `mcp.vProductComponents` view + 3 stock procs via `execute_entity`. Added DB objects: the `mcp` view and one authored proc `dbo.uspGetProductBOM` for the add-a-tool demo.
3. **Cold open:** `read_records` over the `mcp.vProductComponents` view → *"What parts make up the Touring-1000 bike?"* → 14 parts, no SQL.
4. **Add a tool live:** `get_product_bom` custom tool over `dbo.uspGetProductBOM` (87-row recursive BOM).
5. **Back pocket (narrate only):** RBAC role-flip (Simulator / `SalesReader`), Row-Level Security by `SalesPersonID`, not exposing `EmployeePayHistory`, and **vector search via a custom tool** (not a built-in SQL MCP Server tool).
6. **Local auth:** `localhost`, Windows integrated auth (production = managed identity).
