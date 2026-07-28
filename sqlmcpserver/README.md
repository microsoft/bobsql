# SQL MCP Server: Bringing AI Agents to Your SQL Data

**Event:** Visual Studio Live! — Microsoft HQ 2026
**Session:** Tuesday 07/28/2026 · 1:30pm–2:45pm (**75 min**) · Level: **Intermediate**
**Speaker:** Bob Ward — Principal Architect, Microsoft Azure Data

---

## The abstract (as published)

> You've built the databases. You've protected them. Now everyone wants AI to talk to them — and
> they're looking at you to make it happen. **SQL MCP Server** is how you do it safely. Built on
> **Data API Builder (DAB)**, it creates a **governed bridge** between AI tools like GitHub Copilot
> and your SQL Server, Azure SQL, or Fabric SQL Database using the **Model Context Protocol (MCP)**.
> You decide what gets exposed — tables, views, stored procedures — through a **typed, RBAC-enforced
> layer** that agents query without ever touching raw SQL. We'll dig into how it works under the
> hood, walk through the security controls you already care about, and show you how your existing
> SQL skills are exactly what's needed to put AI to work on your data.

## The through-line

**An LLM with a raw connection string is a liability. A governed tool layer is an asset.**
The whole talk answers one question the DBA in the room is already asking: *"How do I let an AI agent
use my data without handing it the keys?"* The answer is the **SQL MCP Server** built on DAB — a
typed, permissioned, stored-procedure-fronted bridge where **the agent calls tools you defined, with
permissions you control, and never emits a line of SQL.**

---

## Everything runs **local** — no cloud dependency

This talk is deliberately self-contained so it runs on a laptop at the venue with **zero cloud egress**:

| Layer | Local implementation | Replaces (Azure version) |
|-------|----------------------|--------------------------|
| **Database** | **SQL Server 2025** — local **Windows** instance on `localhost`, **Windows (Integrated) auth**, stock **AdventureWorks2022** | Azure SQL / Fabric SQL DB, Entra passwordless |
| **Governed bridge** | **DAB / SQL MCP Server** via the `dab` CLI on `http://localhost:5001` (`/api`, `/graphql`, `/mcp`) | Same DAB — would run in Azure Container Apps w/ managed identity |
| **AI agent** | **GitHub Copilot agent mode** in VS Code, MCP server wired in `.vscode/mcp.json` | Same |

**Only the connection string and auth provider change** between this local run and the cloud version —
the DAB config, the entities, the MCP tools, the security model, and the T-SQL are identical. That *is*
the "learn it once, run it anywhere (SQL Server, Azure SQL, Fabric SQL DB)" message the abstract makes.

> **Nothing to redact.** AdventureWorks is Microsoft's public sample database — restored stock, unmodified.

---

## The scenario — Adventure Works

**Adventure Works** is the fictional bicycle manufacturer that ships with Microsoft's canonical
`AdventureWorks2022` sample database — the one every SQL developer and DBA already knows. A **sales-ops
analyst** uses a Copilot agent to ask about **products, bills of materials, orders, and sales reps**
through a governed SQL MCP Server surface. The point is deliberate: **zero schema to learn** means 100%
of the room's attention stays on MCP, DAB, and governance — not on decoding a domain.

**Mostly stock, with minimal additions.** The demo exposes stock AdventureWorks tables plus a small `mcp`
**view** (`mcp.vProductComponents`) for the cold open, and reaches three stock stored procedures
(`dbo.uspGetWhereUsedProductID`, `dbo.uspGetManagerEmployees`, `dbo.uspGetEmployeeManagers`) through the
generic `execute_entity` tool. The one **custom tool** we build — `get_product_bom` — fronts a
purpose-authored proc (`dbo.uspGetProductBOM`) for the recursive bill of materials. DAB fronts these
**same objects** as REST + GraphQL + **MCP tools** with **no middle-tier rewrite** — same objects, three
surfaces. Governance (RBAC, Row-Level Security, not exposing sensitive objects) is covered as part of the
security story.

**Two tool families** (the key mental model — verified against the SQL MCP Server docs, `aka.ms/sql/mcp`):

- **Built-in DML tools** (on by default once MCP is enabled): `describe_entities`, `read_records`,
  `create_record`, `update_record`, `delete_record`, `execute_entity`, `aggregate_records` — a typed
  CRUD surface over every MCP-enabled entity, all RBAC-gated. **No NL2SQL** — DAB builds deterministic
  T-SQL from structured arguments ("NL2DAB"). *Honest nuance:* a DML tool still has the model emit a
  typed **OData filter** (never SQL), which DAB compiles to **parameterized** T-SQL.
- **Custom tools** — a stored-procedure entity marked `mcp.custom-tool: true` becomes a *named,
  described* tool the agent picks by name. In this talk that's **`get_product_bom`** (over an authored
  proc) for the recursive bill of materials the flat view can't express. A custom tool has the model
  emit **nothing but proc parameters** — the airtight "no SQL" claim. Custom tools are also **how you
  expose capabilities the SQL MCP Server has no built-in tool for** — e.g. a **vector / semantic search**
  over embeddings: wrap it in a stored procedure and publish it as a custom tool.

**Controlling the surface is the governance story:** `custom-tool: false` only means "no *named* tool" —
the proc is still invokable via the generic `execute_entity` DML tool **if** the role has `execute`. To
truly withhold write access from the agent, disable the relevant DML tools (globally, or per-entity via
`mcp.dml-tools: false`) and/or scope them to a role the agent doesn't hold — and keep sensitive objects
like `HumanResources.EmployeePayHistory` **unpublished** entirely. **Read/write separation is a config +
RBAC decision — on stage, in seconds.**

---

## SQL MCP Server facts (verified against Microsoft Learn)

Ground truth for rehearsal — pulled from `aka.ms/sql/mcp` →
[`learn.microsoft.com/azure/data-api-builder/mcp`](https://learn.microsoft.com/en-us/azure/data-api-builder/mcp/)
(overview) and [`.../mcp/data-manipulation-language-tools`](https://learn.microsoft.com/en-us/azure/data-api-builder/mcp/data-manipulation-language-tools)
(the tools). Verified 2026-07-23; open-source facts re-verified live against the repo 2026-07-24 — re-check before the talk (DAB moves fast).

| Fact | Detail |
|------|--------|
| **What it is** | **SQL MCP Server is Data API Builder.** `aka.ms/sql/mcp` redirects to the DAB docs. The catalog's "Microsoft SQL" entry = this. There is **no** separate "MSSQL MCP Server" product. |
| **Not to be confused with** | The **MSSQL extension for VS Code** — a *dev-time* schema/**DDL** companion. SQL MCP Server is **data plane only (no DDL)** by design. |
| **Availability** | DAB **1.7+**; use **2.0+** for latest (e.g. `aggregate_records`, custom-tool refinements). |
| **On by default** | Upgrade a working DAB config to 1.7+ and MCP is **already on**; entities participate unless restricted. You configure `runtime.mcp` to *narrow*, not enable. |
| **Tool family 1 — built-in DML** (7) | `describe_entities`, `read_records`, `create_record`, `update_record`, `delete_record`, `execute_entity`, `aggregate_records`. Typed CRUD over every MCP-enabled entity. `read_records` = single table/view, **no JOINs** (use a view or proc). |
| **Tool family 2 — custom tools** | Stored-procedure entities with `mcp.custom-tool: true` → **named** tools via `tools/list` / `tools/call`. Only valid on stored-procedure entities. |
| **No NL2SQL** | Intentional. It's **"NL2DAB"** — the DAB Query Builder emits **deterministic** T-SQL from structured tool args. No free-form model SQL, ever. |
| **Security** | Every tool respects **RBAC** (role → action → field include/exclude), entity permissions, policies, and **RLS**. Same rules across REST, GraphQL, MCP. |
| **Surface control** | Global per-tool toggles (`runtime.mcp.dml-tools.<tool>: false`), per-entity (`mcp.dml-tools: false`), and role permissions. Disabling a tool hides it from `list_tools`. |
| **Transports** | Streamable **HTTP** (`http://localhost:5001/mcp`) and **stdio** (`dab start --mcp-stdio [role:<name>]`). MCP protocol version **2025-06-18**. |
| **Auth (dev)** | **Simulator** provider for role testing offline (stdio defaults to `anonymous`; `role:<name>` to switch). |
| **Ops** | Level-1/2 **caching** on `read_records`; **OpenTelemetry** spans per tool call; **health checks**; App Insights / Log Analytics. |
| **Inspect it** | `npx -y @modelcontextprotocol/inspector http://localhost:5001/mcp` (proxy mode avoids CORS / `Mcp-Session-Id` issues). |

### Open source — verified live against the repo (2026-07-24)

[github.com/Azure/data-api-builder](https://github.com/Azure/data-api-builder):

- **License:** **MIT** (`LICENSE.txt`: *"Copyright (c) Microsoft Corporation. MIT License"*). README: *"Data API builder (DAB) is open source and always free."*
- **Repo health:** Public · ~**1.5k stars** · **353 forks** · **86 contributors** · **98.6% C#**.
- **Latest release: 2.0.9** ("Latest, last month") — **matches the CLI running in this kit** (`2.0.9+17ae3aa…`). (Supersedes the earlier "2.0.9 ~3 weeks ago" note.)
- **MCP is first-class, not a bolt-on:** repo topics **`mcp`** + **`mcp-server`**; About line: *"… modern REST, GraphQL endpoints and **MCP tools** to your Azure Databases and on-prem stores."* MCP landed in **1.7.90** (PR #2868), **custom tools** in #3048, **`aggregate_records`** in #3199 — all in this one repo.
- **Runs anywhere:** container on Azure / any cloud / **on-premises**; requires **.NET 8+** (repo itself is now on .NET 10). Databases: SQL Server, Azure SQL, Fabric SQL DB, PostgreSQL, MySQL, Cosmos DB.
- **Talking point:** *"This isn't a black box — it's MIT-licensed, on GitHub, and the build on my laptop is a public release."*

**Source map (grounding for the architecture diagrams):** the engine is in `src/`; the request-path components are real classes seen in the DAB startup log — the **MCP endpoint / `tools/list` + `tools/call`**, the **Query Builder** (deterministic T-SQL, `Azure.DataApiBuilder.Core.Resolvers`), the **AuthorizationResolver** (RBAC role → action → field), and **`ISqlMetadataProvider`** (proc params / `describe_entities`). Repo also has `docs/`, `schemas/`, `samples/`, `config-generators/`, `docker/`.

---

## Files in this folder

`sqlmcpserver/`

- `outline.md` — the full session outline (this is the working document)
- `README.md` — this file
- `build/` — the local demo kit (a restore of the stock **`AdventureWorks2022`** sample DB, a DAB
  config for the AdventureWorks entities pointed at `localhost`, and the `mcp` schema + view)

## Status

- [x] Local build kit (`build/`) — download + restore stock AdventureWorks, deploy the `mcp` view, validate the DAB config.
- [x] Demo 1 — cold open: agent → `read_records` over `mcp.vProductComponents` (Touring-1000 → 14 parts), no SQL.
- [x] Demo 2 — one config: show / `dab validate` / GraphQL query; per-entity surface control.
- [x] Demo 3 — under the hood: XE capture proves `describe_entities` (no SQL) then a parameterized `read_records`.
- [x] Demo 4 — add a tool live: `get_product_bom` custom tool over `dbo.uspGetProductBOM` (87-row recursive BOM).
- [ ] Back pocket (narrate only): RBAC role-flip (Simulator / `SalesReader`), Row-Level Security by `SalesPersonID`, not exposing `EmployeePayHistory`, vector search via a custom tool.
