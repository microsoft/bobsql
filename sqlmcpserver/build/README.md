# SQL MCP Server — Adventure Works demo kit

Run the "SQL MCP Server: Bringing AI Agents to Your SQL Data" demo on any Windows laptop.
Everything is **local** — SQL Server 2025 on `localhost` (Windows auth), the stock **AdventureWorks**
database, and **Data API builder (DAB)** as the SQL MCP Server over **HTTP on `:5001`**. No cloud egress.

## What you need on the laptop first (not installed by these scripts)

- **SQL Server 2025** local instance on `localhost`, Windows auth, your login = **sysadmin**
- **`sqlcmd`** on PATH (SqlServer command-line tools)
- **.NET SDK** (for the DAB global tool — `setup.ps1` installs the `dab` CLI itself)
- **PowerShell 7+** (scripts are `#requires -Version 7.0`)

## Two commands to go from nothing to live

```powershell
# 1. Build the environment (download + restore AdventureWorks, deploy the view, validate config)
./setup.ps1

# 2. Go live (starts DAB HTTP on :5001 and proves the MCP handshake works)
./start-mcp-http.ps1
```

When `start-mcp-http.ps1` prints **GO LIVE: GREEN**, the MCP protocol is proven working end to end.

## Then in VS Code (the only manual bit — do it in this order)

1. Run `start-mcp-http.ps1` **first** (above) and wait for GREEN.
2. **Then** let VS Code read the config against the live server:
   - Fresh VS Code window → it auto-connects.
   - Already open and the server shows **Stopped** → **Developer: Reload Window** once.
3. **Never edit `.vscode/mcp.json` during the talk** — a mid-session edit is what wedges the
   registration and sticks the server on "Stopped."

The MCP server is registered in **`.vscode/mcp.json`** at the **workspace root** as
`Adventure Works (SQL MCP)` → `http://localhost:5001/mcp`.

## Copying this kit to another repo

Everything here is **location-independent** — no absolute paths. Scripts resolve paths via
`$PSScriptRoot`; the config uses `localhost`. When you copy it:

- Copy the whole `build/` folder (scripts + `dab/` + `sql/`).
- Put **`.vscode/mcp.json`** at the **destination repo's workspace root** (`.vscode/mcp.json`).
  In a **multi-root** `.code-workspace`, VS Code ignores a folder's `.vscode/mcp.json` — put the same
  `servers` block under a top-level `mcp` key in the `.code-workspace` file instead.

## Files

| File | Purpose |
|------|---------|
| `setup.ps1` | One-shot build: download → restore → view → validate. |
| `start-mcp-http.ps1` | Go live: start DAB HTTP on :5001, prove the MCP `initialize` handshake. `-Stop` / `-Restart`. |
| `verify-preflight.ps1` | Read-only checks (DB up, 504 products, view=14, DAB ≥ 2.0.9, `dab validate`, ≤1 DAB proc). |
| `download-adventureworks.ps1` | Download the git-ignored `AdventureWorks2022.bak`. |
| `restore-adventureworks.ps1` | Restore it as `[AdventureWorks]`. |
| `sql/01-mcp-views.sql` | The `mcp` schema + `mcp.vProductComponents` opener view. |
| `dab/dab-config.json` | DAB config exposing `ProductComponents` over REST + GraphQL + MCP. |
| `build.ps1` | Ensure DAB CLI + validate config; also starts the HTTP surface directly if needed. |

## Verify (build is done when all pass)

- `Production.Product` = **504**
- `mcp.vProductComponents` for `Touring-1000` = **14**
- `dab validate` = Config is valid
- `dab --version` ≥ **2.0.9**

`verify-preflight.ps1` asserts all of these in one command.
