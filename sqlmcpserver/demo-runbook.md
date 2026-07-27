# SQL MCP Server — Demo Runbook

Step-by-step to rehearse or present the demos. Everything is **local**: a SQL Server 2025
instance on `localhost` (Windows auth), the stock **AdventureWorks** database, and **Data API
builder (DAB)** as the SQL MCP Server. No cloud egress.

> **Scenario:** Adventure Works (the bike retailer). A sales-ops analyst's Copilot agent queries
> product/BOM/order data through a governed SQL MCP Server. Nothing to redact — AdventureWorks is a
> public sample DB.

Paths are workspace-relative to the **bobsql** root. Kit: `sqlmcpserver/build/`.

---

## Build state (what's actually wired today — 2026-07-26)

| Beat | Status |
|------|--------|
| Demo 1 — cold open, `read_records` over `mcp.vProductComponents` (Touring-1000 parts) | ✅ built + verified live (14) |
| Demo 2 — GraphQL (Nitro) + MCP, **per-entity surface control** (REST off on the view) | ✅ built + verified |
| Config — **13 entities**: 9 read-only tables + the view + 3 `execute_entity` procs | ✅ live on `:5001`, read-only |
| Demo 3 — under the hood (XE capture `demos/demo3-xe-capture.sql`) | ⏳ asset built, not rehearsed |
| Demo 4 — add-a-tool live (`dbo.uspGetProductBOM` → `mcp.custom-tool` = `get_product_bom`) | ✅ built + verified (87 rows, 4 levels) |
| Back pocket — RBAC role-flip, RLS by `SalesPersonID`, don't-expose (CreditCard / EmployeePayHistory), vector | ⏳ narrate only |

Update this table as beats get built.

---

## Pre-flight (do before the room fills)

**If your run includes Demo 2 — one command that also restores the config:**
```powershell
./build/reset-dab-config.ps1
```
Demo 2's live fix **edits** `dab-config.json` (the agent adds `fields`). This restores the committed
baseline (the pristine **12-warnings** start state), validates it, then runs `start-mcp-http.ps1 -Restart`
(full checks + start + MCP handshake). Idempotent — if the config is already pristine it's a no-op copy.
Run this whenever you'll re-run Demo 2 so it starts identically every time.
*(One-time setup, if the baseline ever needs re-capturing from a known-good config: `./build/reset-dab-config.ps1 -Save`.)*

**Cold open only / no config reset — one command, zero clicks (HTTP MCP surface):**
```powershell
./build/start-mcp-http.ps1
```
This runs every scriptable check (DB up, 504 products, view returns 14, DAB CLI ≥ 2.0.9,
`dab validate`), then starts Data API builder as a background **HTTP** server on `:5001` and waits
until a real **MCP `initialize` handshake** succeeds (returns `serverInfo`) — not just "a port
answered." When it prints **GO LIVE: GREEN**, the MCP protocol is proven working end to end. Stop it
after with `./build/start-mcp-http.ps1 -Stop`.

> **Edited the config?** Plain `start-mcp-http.ps1` **reuses** a running server and serves **stale
> config**. After any `dab-config.json` change, use **`-Restart`** to reload (then Reload Window in VS Code).

**Bulletproof order (do it exactly like this — this is what makes it reliable):**
1. Run `./build/start-mcp-http.ps1` **first** and wait for **GREEN**. Server is up + handshake-proven.
2. **Then** let VS Code read the config against the *live* server:
   - Fresh VS Code window → it auto-connects (`.vscode/mcp.json` is valid + the endpoint is up).
   - Already open and the server shows **Stopped** → **Developer: Reload Window** once. Deterministic.
3. **Never edit `.vscode/mcp.json` during the talk.** A mid-session edit (especially an invalid one)
   is exactly what wedges VS Code's registration and makes the server stick on "Stopped." The config
   is committed and valid — leave it alone.

If any check is RED: AdventureWorks missing → `build/download-adventureworks.ps1` then
`build/restore-adventureworks.ps1`; view missing →
`sqlcmd -S localhost -E -C -b -d AdventureWorks -i build/sql/01-mcp-views.sql`.

Then: **Wi-Fi off** to prove it's all local; fonts ≥ 18pt (editor, terminal, MSSQL ext); dark theme.

---

<details><summary>Alternate — stdio MCP server (VS Code-managed, the original talk setup)</summary>

If you deliberately want the stdio surface (VS Code launches DAB, no port), switch the
`Adventure Works (SQL MCP)` entry in `.vscode/mcp.json` back to `type: stdio` and:

1. Run checks only: `./build/verify-preflight.ps1`.
2. **Only ONE SQL MCP server running.** Both talks register a "SQL MCP Server" and DAB hard-codes that
   display name, so run one at a time:
   - **MCP: List Servers** → **stop** `wardgeneral-dab`.
   - **Start** `Adventure Works (SQL MCP)` — *enabling ≠ starting; click **Start**, wait for **Running***.
   - In the chat **tools** picker, make sure only *Adventure Works* is checked.
3. **Warm up the first call** (VS Code cold-start race): ask *"List the AdventureWorks entities."* →
   `describe_entities`. Retry once if the first call errors.

</details>

---

## Demo 1 — Cold open (the anchor)

**Goal:** an agent answers a real question against SQL, writing no SQL.

1. VS Code, **Copilot agent mode**, only *Adventure Works (SQL MCP)* enabled.
2. Prompt: **“What parts make up the Touring-1000 bike?”**
3. The agent runs **two MCP calls**:
   - `describe_entities` → discovers `ProductComponents` (parts/BOM, filter by `ProductModel`).
   - `read_records` with `entity: ProductComponents`, `filter: ProductModel eq 'Touring-1000'` → **14 components**.
4. **Expand the tool call** — show `entity` + `filter` + JSON result. No SQL anywhere.
5. **The line:** *"It asked one question; the server ran one set-based query against a view I own, under
   permissions I control. Same skills you already have — a view, a filter, least privilege — only the
   caller is an agent."*

**Verified result (14 rows):** Chain, Front Brakes, Front Derailleur, HL Bottom Bracket, HL Crankset,
HL Headset, HL Touring Frame, HL Touring Handlebars, HL Touring Seat Assembly, Rear Brakes,
Rear Derailleur, Touring Front Wheel, Touring Pedal, Touring Rear Wheel.

**If it misroutes** (returns clinical data / patient_chart tools): the Ward General server is still
connected — stop it (pre-flight step 3) and retry.

**Talking point — "how does it know it's AdventureWorks?"** The tools are database-agnostic verbs; the
"this is Adventure Works" knowledge is in the **metadata**: the server-level `runtime.mcp.description`
(MCP instructions) + the per-entity/field `description` returned by `describe_entities`. Your
descriptions are the routing layer.

---

## Demo 2 — One config: show it, validate it, query it

**Goal:** you don't write API or server code — you **write and validate config**. Show the file, show the CLI
that manages it, then hit it with a real GraphQL query. (The agent already used the MCP tool on the same
entity in Demo 1.)

### 1) Show & discuss `dab-config.json`
Walk the three sections:
- **`data-source`** — `@env('DAB_CONNECTION_STRING')`: the connection string comes from the **environment**
  (set at DAB startup) — no secrets in the file. `set-session-context: false` (would push the caller's claims
  to SQL for Row-Level Security — off here, no RLS).
- **`runtime`** — `rest` / `graphql` / `mcp` (the three surfaces) and `host` (auth `provider: Unauthenticated`
  → everyone is `anonymous`; `mode: development` → the Nitro playground + detailed errors).
- **`entities`** — the objects you expose. On `ProductComponents`, point at the **per-entity surface toggles**:
  - `"rest": { "enabled": false }` — REST **off** for this entity (on purpose),
  - **no `graphql` block** → GraphQL **on by default**,
  - **no `mcp` block** → MCP tools **on by default**,
  - the entity + field **`description`s** (the routing layer — callback to Demo 3) and `permissions`
    (`anonymous:read` = DAB's RBAC, checked **before SQL**).

  *"One file. No controllers, no resolvers, no MCP server code — and I choose each surface per entity. We'll
  come back here in Demo 3 (how the model reads the descriptions) and Demo 4 (add a tool with one entry)."*

### 2) Basic DAB commands (the CLI that manages this file)
```powershell
dab --version     # 2.0.9 — the DAB global .NET tool
dab --help        # the verbs: init · add · update · configure · validate · start · export
dab validate -c sqlmcpserver/build/dab/dab-config.json
```
`validate` prints **"Config is valid."** — but also **12 warnings**: *"Entity 'Products' is missing 'fields'
definition while MCP is enabled … recommended … for optimal performance with MCP."*

**The teaching point:** *"DAB read the schema at startup, so **DAB** knows the columns — but `describe_entities`
only shows the **model** what's in `fields`. These tables have none, so the agent is blind to their columns.
DAB is telling me to describe them."*

**Live fix (the payoff) — fast, pre-built, deterministic:** run
`./sqlmcpserver/build/reset-dab-config.ps1 -ApplyFields`. It drops in the pre-authored
`dab-config.fields.json` (all **9 tables + 3 stored procs** described), validates to **0 warnings**, and
restarts DAB in one move — then call `describe_entities` to show the model now sees every column. Say to the
agent — *"add all the fields dab validate is warning about"* — and this is the move behind it. There is **no
single `dab` command** that auto-adds fields; the descriptions come from reading the schema, which is the point.
(Hand-authoring recipe + the key `parameters`-vs-`fields` fact is in the run skill.) The `-ApplyFields` path
restarts for you; if you hand-edit instead, **ALWAYS run `start-mcp-http.ps1 -Restart`** — DAB does **not**
hot-reload config, and this keeps the beat identical on every machine.

> **Note on stored procs:** the `missing 'fields'` warning fires for procs too. It's cleared by a `fields`
> block listing the proc's **result-set columns** (not its `parameters`) — that's why the pre-built config
> reaches a clean **0**, not 3.

> **Reset after rehearsal:** `./sqlmcpserver/build/reset-dab-config.ps1` restores the
> 12-warnings baseline so the warnings return for the next run-through.

> Prefer **hand-editing** the config over `dab add`/`dab update` during the talk. Those commands edit the file
> in place, but on save the CLI **reserializes the whole JSON** (in this project it dropped a `//` comment and
> added default props like `request-body-strict`/`autoentities`) — which can reorder what's on screen — and the
> change needs a `-Restart` anyway. Adding a whole entity live is **Demo 4** (hand-edit).

### 3) GraphQL query (Nitro IDE)
DAB serves the **Nitro** GraphQL IDE at `/graphql` in dev mode.
1. Open **`http://localhost:5001/graphql`** → Nitro loads. If prompted for a connection/endpoint, accept the
   default `http://localhost:5001/graphql` and **Create Document**.
2. Paste the query and run it (▶ / Ctrl+Enter):
   ```graphql
   query {
     productComponents(filter: { ProductModel: { eq: "Touring-1000" } }) {
       items {
         ComponentName
         Quantity
         UnitOfMeasure
       }
     }
   }
   ```
   → the right pane shows the same **14 components** (results under `items`).
3. Open the **schema/docs explorer** (left sidebar) → `productComponents`, its `filter`, and the fields are
   all **auto-generated** from the same config. *"I wrote no GraphQL — DAB generated the schema, resolver, and
   filters from the same entity."*
4. **Live-edit** to prove it's real: change the filter to `"Mountain-100"` and re-run.

Notes: the query field is **camelCase plural** (`productComponents`) with results under **`items`**. Nitro is
**dev-mode only** — the `/graphql` endpoint ships to prod, the IDE does not.

**Pre-flight checks (headless, no browser):**
```powershell
# REST is disabled for THIS entity -> 404 (per-entity choice; REST still works on e.g. Products)
try { Invoke-RestMethod 'http://localhost:5001/api/ProductComponents' | Out-Null }
catch { "REST ProductComponents: $($_.Exception.Response.StatusCode) (off on purpose)" }
# GraphQL returns 14
$body = @{ query = 'query { productComponents(filter: { ProductModel: { eq: "Touring-1000" } }) { items { ComponentName } } }' } | ConvertTo-Json
(Invoke-RestMethod -Uri 'http://localhost:5001/graphql' -Method Post -ContentType 'application/json' -Body $body).data.productComponents.items.Count   # expect 14
```

**The line:** *"Same object, same config. I showed the file, validated it with the CLI, and queried it over
GraphQL — and the agent used the MCP tool on that same entity. One file, zero middle-tier code, no rewrite."*

> REST (`/api`), GraphQL (`/graphql`), and the **MCP** endpoint (`/mcp`) all come from the **one** DAB HTTP
> process on `:5001` (started by `start-mcp-http.ps1`) — and each is toggled **per entity** in the config
> (here REST is off for `ProductComponents`, on for the rest). In Azure, DAB is a hosted service; all are HTTPS.

---

## Demo 3 — SQL MCP Server under the hood (peel demo 1)  [VERIFIED 2026-07-26]

**Goal:** re-run demo 1's prompt, but expose the *mechanics* — how a plain-English question becomes
governed, parameterized T-SQL, and where the model's decisions actually come from.

### How it works (reference — narrate these; add more as needed)
- **It's descriptions all the way down** — routing is driven by metadata *you authored*, at two moments:
  1. **Server description** (`runtime.mcp.description`, delivered as the MCP *instructions* at connect) — the
     ONLY domain signal the model has *before any tool runs*. It drives step 1 ("is this a question for this
     server?"). **Make it domain-rich** (products, BOM/parts, orders, customers, sales).
  2. **Entity + field descriptions** (returned by `describe_entities`) — step 2: which entity + which filter
     (e.g., `ProductModel = 'Touring-1000'`).
- **Two discovery moments, two times:** `tools/list` at **connect** (learn the *tools*); `describe_entities`
  **mid-turn, on demand** (learn the *entities*). tools/list is not per-prompt; describe_entities fires only
  when the model needs entity metadata it doesn't already have.
- **`describe_entities` runs NO SQL** — it's an in-memory read of your config (entities, fields, descriptions,
  allowed operations), **RBAC-filtered** to the caller's role. Fast, cheap, *and* a security boundary
  (unauthorized entities aren't even visible to the model).
- **Only the action tools touch SQL** — `read_records` / `execute_entity` compile to **deterministic,
  parameterized T-SQL** (bound, never concatenated). NL2DAB, not NL2SQL.
- **The agentic loop:** model → `describe_entities` → model → `read_records` → model → answer. A **custom**
  (named stored-proc) tool skips `describe_entities` — it's self-describing at connect.
- **Selection = re-score the whole catalog each step** by description match across *all active servers*.
  "Database question" isn't a property of the prompt — it's a match between the prompt's words and the
  metadata you wrote (so a "Touring-1000 parts" question only reaches SQL because the descriptions echo it).

### Show it (steps) — TWO panes: Chat Debug view (model + MCP payloads) + XE (the SQL)

**Before the beat — start the capture and attach SSMS:**
1. Pre-flight the XE session:
   ```powershell
   ./sqlmcpserver/build/start-xe-capture.ps1   # -> XE CAPTURE: GREEN
   ```
   (creates + starts `dab_mcp_capture`, a ring-buffer session filtered to `%ProductComponents%`; idempotent.)
2. In **SSMS**: Management → Extended Events → Sessions → right-click **`dab_mcp_capture`** → **Watch Live
   Data** (a live grid opens, empty). If `sql_text` isn't a column, right-click the header → Choose Columns → add it.

**Run the beat (in Copilot Chat, agent mode, Adventure Works SQL MCP tools ON):**
3. Run the cold open: *"What parts make up the Touring-1000 bike?"*
4. **Chat Debug view** (`/debug`, or the … overflow menu → **Show Chat Debug View**) — expand:
   - **System prompt** → the MCP **server description** (the routing signal the model gets first),
   - **Tool responses** → **`describe_entities`** then **`read_records`** (inputs + outputs). *"This is what the
     model decided, and the payloads it got back."*
5. **SSMS live grid** — `describe_entities` adds **no** row (no SQL); `read_records` lands **one `rpc_completed`**
   → double-click it → `sql_text` = `exec sp_executesql … FROM [mcp].[vProductComponents] WHERE ([ProductModel]
   = @param0) …` with **`@param0 = 'Touring-1000'` bound** (not concatenated).
6. **Land it:** plain English → `describe_entities` (config, **no SQL**) → `read_records` (one **parameterized**
   query, bound param) → JSON. *Descriptions did the routing; DAB did the SQL. NL2DAB, not NL2SQL.*

**Teardown:** `./sqlmcpserver/build/start-xe-capture.ps1 -Stop` (drops `dab_mcp_capture`).

**Verified notes (2026-07-26):**
- Two `rpc_completed` rows may appear (the agent reads twice) — both identical + parameterized.
- `SELECT TOP 101` = keyset **pagination** probe (page size + 1) — a nice "production-grade, not a toy" aside.
- The **reader-script self-match** (`sql_batch_completed`) only shows if you run the .sql *reader* (its comments
  contain "ProductComponents"). **SSMS Watch Live Data** + the `%ProductComponents%` filter shows only the clean
  agent `rpc_completed`.
- **Prereq gotcha:** start the XE session BEFORE the prompt, and make sure the run routes through the **MCP tools**
  (GraphQL/REST hit the same view but that's a different beat). The MCP server must be up (`:5001`) with its tools
  toggled on in the chat's Configure Tools.
- **Tried and dropped:** VS Code **Agent Logs** (preview) — thin/empty on this build; **Chat Debug view** is the
  keeper for the model side. DAB `--LogLevel Debug` and a logging proxy were considered and are **not needed**.

---

## Demo 4 — Add a tool live (custom tool over a stored proc)  [BUILT · verified 2026-07-26]

**Goal:** widening what agents can do is a *config* change, not code. Take a stored procedure, expose it as a
**named MCP tool** with one block of config, restart, and watch the agent discover and call it.

**Why it lands after Demo 1:** the cold open returned a *flat* parts list from a view. `read_records` can't
express a **recursive, multi-level bill of materials** — that logic lives in a proc. Promote the proc to a tool
and the agent gains a capability the generic tools can't provide.

**Payoff numbers (verified):** the view returns **14 top-level parts**; `get_product_bom('Touring-1000')`
returns the **full 87-row, 4-level recursive assembly** the generic tools can't express.

### The proc (BUILT): `build/sql/02-demo4-bom-proc.sql`

`dbo.uspGetProductBOM @ProductModel nvarchar(50)` resolves the model name → a representative `ProductID`, then
returns the full recursive BOM. **Critical gotcha:** the recursive CTE is **INLINED** (not `EXEC
dbo.uspGetBillOfMaterials`). A proc that returns its result set via a **nested `EXEC`** yields NULL from
`sys.dm_exec_describe_first_result_set`, so **DAB can't build the entity and `dab validate` fails "Config is
invalid."** Inlining makes the proc's own final `SELECT` describable. Deployed automatically by `setup.ps1`
(step 3b). It is keyed by MODEL name so it matches the cold open exactly ("Touring-1000") with no second entity.

### Two ways to run the payoff

**Deterministic (recommended) — `-ApplyTool`.** Mirrors Demo 2's `-ApplyFields`. Drops in the pre-built,
**validated** config that adds the tool, then restarts:
```powershell
./build/reset-dab-config.ps1 -ApplyTool     # applies dab/dab-config.tool.json, validates, restarts DAB
```
Reset afterward so the tool is NOT in the baseline (adding it live IS the demo):
```powershell
./build/reset-dab-config.ps1                 # restore baseline (12-warnings start state), restart
```

**Live hand-edit (more theatrical).** Add the entity with the CLI, then hand-add the description + parameter
(the CLI truncates `--description` at the first comma, so hand-edit the JSON):
```powershell
dab add GetProductBOM -c <abs path to dab/dab-config.json> `
  --source dbo.uspGetProductBOM --source.type "stored-procedure" `
  --permissions "anonymous:execute" --mcp.custom-tool true
```
Then the entity in `dab-config.json` should read (this exact block is committed as `dab/dab-config.tool.json`):
```jsonc
"GetProductBOM": {
  "description": "Returns the FULL multi-level bill of materials (every component part, recursively, with quantities and costs) for a product MODEL name, e.g. 'Touring-1000'. Use this when a flat top-level parts list is not enough and you need the complete assembly tree.",
  "source": {
    "object": "dbo.uspGetProductBOM",
    "type": "stored-procedure",
    "parameters": [
      { "name": "ProductModel", "description": "Product model name, e.g. 'Touring-1000'. Resolved to a ProductID, then its full recursive bill of materials is returned.", "required": true, "default": "Touring-1000" }
    ]
  },
  "mcp": { "custom-tool": true },
  "permissions": [ { "role": "anonymous", "actions": [ { "action": "execute" } ] } ]
}
```
Tool name in `tools/list` is snake_case: **get_product_bom**.

**Restart DAB with `./build/start-mcp-http.ps1 -Restart`** — entity/config changes are NOT hot-reloaded, and
plain `start-mcp-http.ps1` (no flag) **reuses the running server and serves stale config**. `-Restart` reloads
it and re-proves the handshake. If VS Code shows the server **Stopped** after, run **Developer: Reload Window** once.

### Pre-flight (fast)
No separate server needed — `-ApplyTool` **validates** `dab-config.tool.json` as part of applying it. If you
want a quick config-only check without going live:
```powershell
$env:DAB_CONNECTION_STRING = "Server=localhost;Database=AdventureWorks;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;"
dab validate -c ./build/dab/dab-config.tool.json   # expect "Config is valid."
```
(One-time proof already captured: the tool advertises as `get_product_bom` and returns **87 rows, BOMLevel up
to 4** for Touring-1000.)

### Run the beat — reuse the SAME cold-open prompt
The payoff is that you **don't change the question** — you changed the server's capabilities via config.

1. Before (Demos 1–2 config): only the view exists. Cold open *"What parts make up the Touring-1000 bike?"*
   → `read_records` on the view → **14 top-level parts**.
2. Switch configs: `./build/reset-dab-config.ps1 -ApplyTool` (validates + restarts DAB; proc already in the DB
   from build). Reconnect (Reload Window once if VS Code shows Stopped).
   - **Show it in the chat's Configure Tools flyout:** open the tools picker (the 🛠️ / "Configure Tools"
     control under the chat box) and point out that **`get_product_bom` now appears** in the SQL MCP server's
     tool list — it wasn't there before the switch. The config change literally added a new tool to the agent's
     toolbox; you can see it land in the UI before you even ask a question.
3. Same prompt again: *"What parts make up the Touring-1000 bike?"*
   **Observed live (2026-07-26):** the agent first returns the view's **flat 14**, then *proactively offers*
   "want the deeper, multi-level breakdown?" and, on yes (or in the same turn), calls **get_product_bom** →
   the **87-row, 4-level recursive BOM**. That two-step — flat list, then an offer to go deeper — is a *better*
   beat than a hard swap: the agent shows it picked the right tool for "the complete assembly." The tuned
   descriptions drive it (view = "quick FLAT top-level list"; `get_product_bom` = "the COMPLETE multi-level
   BOM, every part, all the way down").
   - If your model doesn't volunteer the deeper call, one nudge: *"yes, the full multi-level breakdown."*
4. Land it: *"Same question. No glue code. A stored proc became an agent tool via config + a good description —
   and the agent knew when to reach for it."* Tie back to Demo 3: a custom tool is self-describing at connect,
   so it skips `describe_entities`.

---

## Cut for time / back pocket

Kept for Q&A or a longer slot; not in the main run.

### RBAC role-flip — "denied before SQL"
Two layers people conflate: **authentication** (identity→role: bearer token / `role:` over stdio /
`X-MS-API-ROLE`) vs **authorization** (DAB per-entity `permissions` = the **① Authorize** step). A role without
the action is denied **before SQL**. To exercise real roles offline, set `host.authentication.provider` to
`Simulator`, grant e.g. `SalesReader:execute`, **restart** (not hot-reloaded), then call with header
`X-MS-API-ROLE: SalesReader` (HTTP) or `dab start --mcp-stdio role:SalesReader`. Notes: `Unauthenticated`
collapses every role to `anonymous`; `custom-tool: false` doesn't block a proc if the role still has `execute`.

### Row-level security (RLS)
- `SECURITY POLICY` on `Sales.SalesOrderHeader` filtered by `SalesPersonID` — enforced in SQL no matter which
  tool calls. Pairs with the RBAC beat: RBAC gates *the tool*, RLS gates *the rows*.

### Don't-expose
- Leave `HumanResources.EmployeePayHistory` unpublished (or `dml-tools: false`) — invisible to agents.

### Vector / semantic search — MENTION ONLY (not a live demo)
- There is **no built-in vector tool**. Wrap `VECTOR_SEARCH` in a stored proc (the query embedding is a
  parameter) and expose it as a **custom tool** — e.g. `SearchSimilarProducts` over
  `Production.ProductDescription` + Foundry Local. Same pattern as Demo 4: semantic search is just another
  custom tool.

---

## Teardown / reset between rehearsals

- Stop the DAB HTTP server: `./build/start-mcp-http.ps1 -Stop` (or `-Restart` to bounce it).
- (Alternate stdio setup only: stop it from **MCP: List Servers** — VS Code manages that process.)
- The database persists; nothing to clean up.
