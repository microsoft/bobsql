---
name: build-sqlmcpserver-demo
description: >-
  Build / provision the LOCAL demo environment for the "SQL MCP Server:
  Bringing AI Agents to Your SQL Data" (Adventure Works scenario) on this machine,
  so the demos will run. USE WHEN the presenter says any of: "build the sqlmcpserver
  demo environment on this machine", "set up the SQL MCP Server demo kit", "build
  the SQL MCP Server demo environment", "provision the AdventureWorks demo on this laptop",
  "get the SQL MCP demo ready on this box", or moves the talk to a new machine and
  needs AdventureWorks + the view + a validated DAB config in place. Scope is
  DOWNLOAD + RESTORE + SCHEMA/VIEW + VALIDATE CONFIG + VERIFY + check MCP
  registration ONLY. Do NOT use to run/rehearse the demos (that's
  run-sqlmcpserver-demos), to build the database/kit for the Ward General /
  hyperscale talk (separate), or to author slides.
---

# Build the SQL MCP Server demo environment

Stand up everything the SQL MCP Server demos need on **this** machine, then verify. Everything
is **local** — a SQL Server 2025 instance on `localhost` with **Windows integrated
auth**, the stock **AdventureWorks** database, and **Data API builder (DAB)** as the
SQL MCP Server. No cloud egress.

All paths are workspace-relative to the **bobsql** root. Kit:
`sqlmcpserver/build/`. Run `.ps1` scripts **synchronously**
(`isBackground:false`, `timeout:0`); check exit codes; one command per call.

## Prereqs to check first (do NOT try to install these — stop and tell the presenter if missing)

- **SQL Server 2025** local instance reachable on `localhost` via Windows auth
  (current login = sysadmin). No container, no `sa`.
- **`sqlcmd`** on PATH (SqlServer command-line tools).
- **.NET SDK** (for the DAB global tool).
- **PowerShell 7+** (scripts are `#requires -Version 7.0`).

Quick gate:
```powershell
sqlcmd -S localhost -E -C -Q "SELECT @@VERSION;"     # instance reachable via Windows auth?
Get-Command sqlcmd, dotnet, pwsh -ErrorAction SilentlyContinue
```

## Build procedure — one command

```powershell
& sqlmcpserver/build/setup.ps1
```
`setup.ps1` is the one-shot build. It:
1. Checks host prereqs (sqlcmd, dotnet, pwsh; SQL reachable via Windows auth) and aborts if missing.
2. Downloads `AdventureWorks2022.bak` (git-ignored; skipped if already present).
3. Restores it as `[AdventureWorks]` (Windows auth).
4. Deploys the `mcp` schema + `mcp.vProductComponents` view.
5. Ensures the DAB CLI and runs `dab validate` on `build/dab/dab-config.json`.

(The individual scripts — `download-adventureworks.ps1`, `restore-adventureworks.ps1`,
`sql/01-mcp-views.sql`, `build.ps1 -NoStart` — still exist if you need to run a single step.)

## Verify — one command

```powershell
& sqlmcpserver/build/verify-preflight.ps1
```
Read-only. Asserts: DB up, `Production.Product` = **504**, `mcp.vProductComponents` for `Touring-1000`
= **14**, `dab --version` ≥ **2.0.9**, `dab validate` passes, ≤ 1 DAB process. Exit 0 = all green — that
is the definition of "built."

## MCP surface + registration (HTTP)

The MCP server is now **HTTP on `:5001`**, not stdio. `.vscode/mcp.json` (workspace root) registers
`Adventure Works (SQL MCP)` → `http://localhost:5001/mcp`. The kit is **location-independent** (scripts
resolve paths via `$PSScriptRoot`; the config uses `localhost`) — nothing to edit when the repo path
changes. REST (`/api`), GraphQL (`/graphql`), and MCP (`/mcp`) all come from the one `:5001` process.

Going live is the **run** skill's job, not this one; for reference the go-live command is:
```powershell
& sqlmcpserver/build/start-mcp-http.ps1   # starts DAB HTTP :5001, proves the MCP handshake → GREEN
```
`wardgeneral-dab` (:5000) is the other talk's server — harmless, leave it.

## Optional (only if the demo has been built)

- **Demo 4 (add-a-tool)** proc: if `build/sql/` gains the BOM proc (`uspGetProductBOM`), deploy it with
  `sqlcmd ... -i` the same way as the view, then re-run `verify-preflight.ps1`. As of last edit this is
  **pending a design decision** — skip unless present.

## Do NOT

- Install SQL Server, .NET, or sqlcmd — `setup.ps1` checks and reports; it does not provision the host.
- **Go live** (`start-mcp-http.ps1`) or drive the demos here — that's `run-sqlmcpserver-demos`. This skill
  leaves a *validated, verified* environment.
- Touch the Ward General / hyperscale kit or author slides.

## Done =

`setup.ps1` completed and `verify-preflight.ps1` is all green (504 products, view = 14 for Touring-1000,
`dab validate` passes, DAB ≥ 2.0.9). Hand off to `run-sqlmcpserver-demos` (which runs `start-mcp-http.ps1`
and drives the beats).
