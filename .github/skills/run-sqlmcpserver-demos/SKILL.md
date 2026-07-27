---
name: run-sqlmcpserver-demos
description: >-
  Drive the live demos for the "SQL MCP Server: Bringing AI Agents to
  Your SQL Data" (Adventure Works scenario, local SQL Server 2025 + Data API
  builder + VS Code Copilot agent). USE WHEN the presenter says any of: "let's
  start the SQL MCP Server demos", "let's start the SQL MCP demos", "start the SQL
  MCP Server demos", "let's do the demos", "let's
  run through the demos", "run the SQL MCP Server demos", "run the SQL MCP demos",
  "rehearse the SQL MCP talk", "practice the Adventure Works demo", "let's do the
  cold open", "run pre-flight", "let's run pre-flight", "pre-flight the SQL MCP
  demo", "check the demo is ready", or wants step-by-step help executing the
  AdventureWorks SQL MCP
  Server demos (pre-flight checks, starting the right MCP server, the Touring-1000
  cold open, the REST/GraphQL three-surfaces beat). Scope is RUN/REHEARSE the SQL
  MCP Server demos ONLY. Do NOT use to build the database/kit (that's the build scripts)
  or to author slides.
---

# Run the SQL MCP Server demos

Help the presenter execute the SQL MCP Server demos, one beat at a time, doing the right
steps in the right order. The single source of truth for the steps is the
runbook: **`sqlmcpserver/demo-runbook.md`** — read it first, then
drive from it. The narrative/timing lives in `sqlmcpserver/outline.md`.

All paths are workspace-relative to the **bobsql** root. Kit:
`sqlmcpserver/build/`. Everything is local — no cloud egress.

## How to help

1. **Read `demo-runbook.md` first** every time — it has the current build state
   table (which beats are wired vs. TBD) and the exact commands/prompts. Do not
   invent steps that aren't there.
2. **Always run pre-flight before the first demo** (runbook "Pre-flight"):
   - **Standard pre-flight (restores Demo 2 config + goes live): `build/reset-dab-config.ps1`.** It
     restores `dab-config.json` from the committed baseline (the pristine **12-warnings** Demo 2 start
     state), validates it, then calls `start-mcp-http.ps1 -Restart` (full checks + start + MCP handshake).
     **Run this whenever the demo run includes Demo 2** — Demo 2's live fix edits the config, so restoring
     the baseline first is what lets it be run again identically. (Idempotent: if the config is already
     pristine, the restore is a no-op copy.)
   - **Lighter path (no config reset): `build/start-mcp-http.ps1`.** Same checks + start + handshake, but
     does **not** touch `dab-config.json`. Use when you're only doing the cold open / not re-running Demo 2.
     On **GO LIVE: GREEN**, VS Code connects via `.vscode/mcp.json` (`http://localhost:5001/mcp`). Stop with `-Stop`.
   - **Checks only** (or for the stdio alternate): `build/verify-preflight.ps1` — asserts DB reachable,
     504 products, view returns 14 for Touring-1000, `dab --version` ≥ 2.0.9, `dab validate`, and that
     **≤ 1** DAB process is up.
   - **Only if using the stdio surface:** stop any OTHER SQL MCP server, then **Start**
     `Adventure Works (SQL MCP)` in *MCP: List Servers* (enabling ≠ starting), and warm up the first
     call (cold-start race — retry once). The HTTP path above avoids all of this.
3. **Drive one beat at a time.** State which demo you're on, show/run its steps,
   confirm the expected result, then ask before moving to the next.
4. **Verify with tools when useful.** You can call the AdventureWorks MCP tools
   directly (`describe_entities`, `read_records`) to prove a beat works before the
   presenter runs it in agent-mode chat. Load them with tool_search if deferred.
5. **If the agent misroutes** (returns tools/data you don't recognize): another MCP
   server is still connected — stop it and retry. This is the #1 gotcha.

## The beats (see the runbook for exact steps)

- **Demo 1 — Cold open:** prompt *"What parts make up the Touring-1000 bike?"* →
  agent calls `describe_entities` then `read_records` (filter `ProductModel eq
  'Touring-1000'`) → **14 components**, no SQL authored by the model.
- **Demo 2 — One config, show/validate/query:** (1) show & discuss `dab-config.json`
  (per-entity surface toggles — REST off on the view, GraphQL/MCP default on), (2) basic
  DAB commands — `dab --version` / `--help` / `validate`; validate prints "Config is
  valid" **plus 12 "missing fields" MCP warnings**; on request, **add the fields live**
  (recipe below), (3) a GraphQL `productComponents` query in Nitro → 14.
- **Demo 3 — Under the hood:** peel Demo 1 — server-description routing,
  `describe_entities` (no SQL), `read_records` → parameterized T-SQL. TWO panes:
  **Chat Debug view** (`/debug` → System prompt = server description, Tool responses =
  `describe_entities`/`read_records` payloads) + **XE via SSMS Watch Live Data**. Pre-flight the
  capture with `build/start-xe-capture.ps1` (creates+starts `dab_mcp_capture`) BEFORE the prompt;
  `describe_entities` = no row, `read_records` = one `rpc_completed` with bound `@param0`.
  Teardown `build/start-xe-capture.ps1 -Stop`. (Agent Logs preview was thin — not used.) ✅ verified 2026-07-26.
- **Demo 4 — Add a tool live:** expose `dbo.uspGetProductBOM` as a `custom-tool`, restart, the
  agent discovers **`get_product_bom`** — the recursive BOM the view can't do (view = 14 top-level
  parts; tool = 87 rows, 4 levels). Deterministic payoff: `build/reset-dab-config.ps1 -ApplyTool`
  (applies `dab/dab-config.tool.json`, validates, restarts); reset with plain `reset-dab-config.ps1`.
  The proc INLINES the recursive CTE (a nested `EXEC` breaks
  `describe_first_result_set` and fails `dab validate`). ✅ built + verified 2026-07-26.
- **Back pocket (not in the main run):** RBAC role-flip, RLS by `SalesPersonID`,
  don't-expose `EmployeePayHistory`, vector search (mention only).

## Demo 2 live fix — "add the fields dab validate is warning about"

There is **NO single `dab` command** that auto-adds fields. Two ways to do the fix:

**FAST PATH (recommended for the live talk) — pre-built, instant, deterministic:**
When the presenter asks (after `dab validate` shows the "missing 'fields'" warnings), run:
```powershell
./sqlmcpserver/build/reset-dab-config.ps1 -ApplyFields
```
This drops in the pre-authored `dab-config.fields.json` (all **9 tables + 3 stored procs**
described), validates to **0 warnings**, and restarts DAB — one move, ~seconds, identical
every time. Then call `describe_entities` to show the model now sees the columns. Reset for
the next run with `./reset-dab-config.ps1` (restores the 12-warnings baseline).

**MANUAL PATH (only if you want to hand-author live to make a teaching point):**
1. Note the warned entities — the **9 tables** AND the **3 stored procs**.
2. For each warned TABLE, get its columns (schema/table = the entity's `source.object`):
   ```powershell
   sqlcmd -S localhost -E -C -W -d AdventureWorks -Q "SET NOCOUNT ON; SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='Sales' AND TABLE_NAME='SalesOrderHeader' ORDER BY ORDINAL_POSITION;"
   ```
   For each warned PROC, get its **result-set** columns (that is what a proc's `fields`
   describes — NOT its parameters):
   ```powershell
   sqlcmd -S localhost -E -C -W -d AdventureWorks -Q "SET NOCOUNT ON; SELECT name FROM sys.dm_exec_describe_first_result_set(N'EXEC dbo.uspGetManagerEmployees @BusinessEntityID=2', NULL, 0) ORDER BY column_ordinal;"
   ```
3. Edit `dab-config.json`: add a `fields` array (sibling of `source`) to that entity — each
   column as `{ "name": "<col>", "description": "<short business description>" }`. Valid
   JSON; don't touch the other entities.
   - **Key fact (verified on DAB 2.0.9):** the `missing 'fields'` warning is keyed purely on
     the presence of a top-level `fields` array. Adding proc **`parameters`** does NOT clear
     it — only a **`fields`** block does. A `fields` block on a proc is additive metadata; it
     does not project/restrict the result set (the proc still returns all columns).
4. Re-run `dab validate` → confirm warnings gone ("Config is valid", **0** MCP warnings).
5. **ALWAYS restart** so the change takes effect the same way every time:
   `start-mcp-http.ps1 -Restart`, then call `describe_entities` to show the model now sees
   the columns. (DAB does **not** hot-reload config — without `-Restart` it serves stale
   config. This step is mandatory, not optional, so the beat is identical on every machine.)
6. **RESET after rehearsal:** `git checkout -- sqlmcpserver/build/dab/dab-config.json`
   (returns to the 12-warnings baseline so the warnings come back next run).

Snappy is fine — the fast path adds all 12 entities in one move. Descriptions are short and
useful (not one word); they're what the model reads via `describe_entities`.

## Key facts / gotchas

- **DB:** local SQL Server 2025, `localhost`, **Windows integrated auth** (no
  container, no sa). AdventureWorks restored as `[AdventureWorks]`.
- **MCP registration:** `.vscode/mcp.json` (workspace root) — `Adventure Works (SQL
  MCP)` is now **HTTP** on **:5001** (started by `start-mcp-http.ps1`). REST `/api`,
  GraphQL `/graphql`, and MCP `/mcp` all come from the one :5001 process. A **stdio**
  setup still works as an *alternate* (runbook collapsible section); if you use it, the
  flag is `--LogLevel` (capital).
- **Opener is a VIEW + `read_records`** (built-in DML tool), deliberately — one
  question → one set-based query. It is NOT a custom-tool/stored-proc opener.
- **After any config edit, use `start-mcp-http.ps1 -Restart`** — the plain command
  *reuses* a running DAB and serves **stale config** (verified: it kept serving the old
  server description until `-Restart`). This matters most in **Demo 4 (add-a-tool)**:
  without `-Restart` the new `get_product_bom` tool won't appear.
- **DAB CLI stdio flag** is `--LogLevel` (capital), not `--loglevel`.
- Do not start both MCP servers at once; the tools flyout can't tell them apart.

## Do NOT

- Build/restore the database or edit `dab-config.json` schema here — that's the
  build kit's job (`download-`/`restore-adventureworks.ps1`, `build.ps1`,
  `sql/01-mcp-views.sql`).
