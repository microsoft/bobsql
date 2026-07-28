# Chat session — 2026-07-19 (pt.3) · App front end + DAB/MCP committed

Builds on [2026-07-19_scenario-switch-wardgeneral.md](2026-07-19_scenario-switch-wardgeneral.md).

## App built (book repo)

- `hyperscalebook/examples/ch04/app/` — .NET 10 console, `Microsoft.Data.SqlClient`,
  Entra auth (no secrets), stored-proc DAL. Builds clean. Validated against live
  `wardgeneral` (server `collierhealth-ew111025.database.windows.net`, HS_Gen5_8, compat 170).
- DAL is UI-agnostic: `Data/{ChartRepository,WardGeneralConnectionFactory,RetryPolicy}.cs`,
  `Models/ChartModels.cs`.

## Decisions

1. **Front end = Blazor Web App (.NET 10), reuse the DAL.** Console stays as a smoke test.
   (Not yet built — next.)
2. **Hosting = Azure App Service**, pre-deployed with **system-assigned managed identity**
   (= the Secure-it "no secrets" beat). Everything built/deployed ahead; **nothing on
   stage** — the session just *shows* what's already running.
3. **DAB + SQL MCP promoted from optional → committed** "Modernize it" beats, "Path A":
   **app (ADO.NET) → DAB (REST/GraphQL, no code) → MCP (agent tools)** — same 11
   `clinical.*` procs, three surfaces, no rewrite. This is why the book chose stored procs.

## DAB/MCP facts verified on Learn (2026-07-19)

- MCP is configured in `dab-config.json`; DAB **1.7+** auto-enables SQL MCP Server; use **2.0+**.
- **No `runtime.mcp` global key** — MCP is per-entity: `mcp.custom-tool: true` on a
  stored-procedure entity registers it as a named MCP tool (`tools/list`/`tools/call`).
- Stored-proc entity: `source.type: stored-procedure`, `source.parameters`,
  `rest.methods`, `graphql.operation`, `permissions[].actions: [execute]`.
- Limitation: stored-proc tools return **first result set only**; no paging/filter/order.
- Runtime keys confirmed: `runtime.rest`, `runtime.graphql`, `runtime.host.{mode,cors,authentication}`.

## Artifact created

- `hyperscalebook/examples/ch04/dab/dab-config.json` — DRAFT mapping all 11 procs to
  REST + GraphQL + MCP custom tools. Connection via `@env('DAB_CONNECTION_STRING')`
  (passwordless / managed identity — no secret in file). Perms currently `anonymous:execute`
  for demo simplicity — tighten to authenticated + RBAC for the Secure story / book Ch 8.

## Outline updated

- Modernize section rewritten to 3 beats: (1) new T-SQL JSON+Regex, (2) app→DAB→MCP,
  (3) AI clinical-notes vector search. Time-budget §5 + demo-asset inventory updated
  (DAB + MCP rows). AI row now reaches data via MCP.

## Still OPEN — resolve before building the `build/` kit

- **Where does the self-contained `build/` kit live, and does the app move there?**
  Earlier ask: talk folder `presentations/hyperscale-developer/build/` with `sql/`
  (copied ch02 scripts), an app subfolder, `build.ps1` (builds the .NET app). But the app
  currently lives in the **book repo** (`examples/ch04/app/`). Decide: talk kit
  *references* the book artifacts vs *duplicates* them. **Not yet created.**

## Next

- Confirm build-kit location (above).
- Build the Blazor front end on the DAL.
- Provision App Service + managed identity; grant DB access to the MI.
- Deploy DAB container (config above) with its own MI; enable MCP.
- JSON+Regex SSMS scripts; AI beat (embed `ClinicalNote`, vector index, search proc).
