# Chat session — 2026-07-19 (pt.4) · Self-contained kit, Blazor app, DAL lib, skills

Builds on [2026-07-19_app-dab-mcp.md](2026-07-19_app-dab-mcp.md).

## Hard constraint (author, 2026-07-19)

**The talk must NOT reference the book** — the book is confidential ("no one knows
I'm writing this"). Everything the talk uses is **self-contained in the talk kit** and
scrubbed of book/chapter references.

## Done this session

1. **Self-contained `build/` kit** at `presentations/hyperscale-developer/build/`:
   copied SQL (`sql/`), the app, and `dab/dab-config.json` from the book repo, then
   **scrubbed ~48 book references** ("Azure SQL Hyperscale Unveiled — Chapter 2",
   "Ch 5/8/10", "book", etc.) from all SQL + C# + DAB files. Verified clean.
2. **`build.ps1`** — builds the .NET app.
3. **Console app → Blazor + class-library restructure** (Option A hosting = App Service;
   containers/ACA considered but App Service chosen for the on-prem audience):
   ```
   build/
     src/WardGeneral.Data/   class library (DAL): ChartRepository, ConnectionFactory,
                             RetryPolicy, Models/ChartModels  — namespaces WardGeneral.Data(.Models)
     src/WardGeneral.Web/    Blazor Web App (Interactive Server) → refs WardGeneral.Data
       Pages/Home.razor      encounter list (SearchEncounters)
       Pages/Chart.razor     patient chart, 5 json sections as cards
     WardGeneral.slnx        solution
   ```
   Console app deleted. **Solution builds clean** (net10.0).
   - DAL is its own **class library** so it's reusable (in-process with the web app;
     one deployed unit — App Service hosts just the web app, DAL DLL bundled in).
4. **Skill authored:** `skills/build-wardgeneral-app/SKILL.md` — build/configure/run the
   app against Hyperscale (passwordless Entra auth, build.ps1, `dotnet run`).

## Decisions locked

- Front end = **Blazor Web App** (not console). Console app dropped.
- Hosting = **Azure App Service** (deploy ahead of time; nothing provisioned on stage).
  Containers/ACA + Aspire discussed; App Service chosen (familiar to on-prem SQL devs).
- DAL = **class library** `WardGeneral.Data` (reused by the web app; reusable later).
- App connection: `WardGeneral:Server`/`Database` in appsettings; `ActiveDirectoryDefault`
  auth — **no secret**. Server `collierhealth-ew111025.database.windows.net`.

## Still OPEN / next

1. **Pull in the book's DB-deploy skill** (`deploy-hyperscale`) — SCRUBBED for the talk.
   Needs: copy `provision-hyperscale.ps1` (+ decide which ops scripts: scale / pitr /
   verify-activity-log / estimate-cost / add-replicas) into the kit, rewrite its book
   paths to `build/sql/`, and strip chapter references. **Decision needed:** which
   scripts to bring + where they live (e.g. `build/deploy/`).
2. **Book-repo cleanup:** the app + dab I first built in `hyperscalebook/examples/ch04/`
   are now duplicated in the talk kit. `ch04/` was empty before this session — decide
   whether to remove `examples/ch04/{app,dab}` to restore it. (Not done; flagged.)
3. Skills location: currently `presentations/hyperscale-developer/skills/`. To activate in
   VS Code they'd be copied to `.github/skills/`. Kit-local keeps them portable.
4. Then: App Service deploy (+ managed identity → DB grant), DAB container + MCP, AI beat.
