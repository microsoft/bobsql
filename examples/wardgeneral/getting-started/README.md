# Getting Started — Getting Started

Provision an Azure SQL **Hyperscale** database, connect to it, build the
through-line schema, and seed it with fully synthetic data. This is the database
every later area builds on: the **Ward General Hospital** database
(`wardgeneral`) on the **Collier Health** logical server (`collierhealth`).

> **New here?** Read the [repository README](../../README.md) first — it covers the
> scenario, prerequisites (VS Code, GitHub Copilot, PowerShell 7, Azure CLI, the
> MSSQL extension, an Azure subscription), and how to run the guided deploy with
> the `deploy-hyperscale` Copilot skill.

## The flow

Five moves, in order:

1. **Deploy** — create the logical server + Hyperscale database (`provision-hyperscale.ps1`).
2. **Add the replicas** — run `add-replicas.ps1` for a second HA replica and the
   `wardgeneral-research` named replica. This finishes the provision step:
   Architecture examines that named replica as an architectural object, and Area
   5's Research page is the first thing to actually use it — both assume it
   exists.
3. **Connect & prove it's SQL Server** — run `connect-and-verify.sql`.
4. **Build the schema** — run `01`→`04` in order.
5. **Seed & verify** — run `05-seed.sql`, then `verify-data.sql`.

You can drive all of this through Copilot (ask it to *"deploy my Hyperscale
database"* and it runs the `deploy-hyperscale` skill), or run the scripts by hand
as described below.

> **Tip — a third way to verify.** After the deploy, run
> `verify-activity-log.ps1` for a control-plane check: it summarizes the Azure
> Activity Log (every operation that built the database) and flags any failures.
> That's the deploy proof; `connect-and-verify.sql` is the tier proof and
> `verify-data.sql` is the data proof — same database, three angles.

## Files in this folder

| File | Type | What it does |
|---|---|---|
| `provision-hyperscale.ps1` | PowerShell | Creates `rg-collierhealth`, the `collierhealth` logical server, and the `wardgeneral` Hyperscale database in one `az sql db create` — provisioned, single, **1 HA replica, zone-redundant, GeoZone backup**. Mixed SQL + Entra auth. Calls `estimate-cost.ps1` at the end. |
| `estimate-cost.ps1` | PowerShell | Prints a live, itemized monthly cost estimate for the deployed Hyperscale shape from the public Azure Retail Prices API, plus the deploy-time cost-vs-resilience levers (inside Hyperscale, drop the HA replica / zone redundancy ≈ −50% compute; Zone vs GeoZone backup). For GP ZR comparisons, use the Azure portal cost summary or Pricing Calculator because GP ZR uses a different meter shape. No dollar figures are hard-coded. |
| `verify-activity-log.ps1` | PowerShell | Read-only control-plane check: summarizes the Azure **Activity Log** for `rg-collierhealth` (every operation ARM ran to build the database) — events by status, by operation, most-recent table, and a **failure flag**. A clean deploy shows all `Succeeded`. Widen the window with `$env:OFFSET='1d'` (default 6h). |
| `connect-and-verify.sql` | SQL | Proves it's SQL Server: `@@VERSION`, `DATABASEPROPERTYEX`, service objective, and the governing limits (workers, sessions, log rate, IOPS, memory, 128 TB ceiling, collation, compatibility level) in human units. |
| `01-schemas.sql` | SQL | Creates the `clinical` and `ops` schemas. |
| `02-tables.sql` | SQL | Creates all 16 tables — clustered keys, FKs, constraints, and the four native `json` columns. |
| `03-views.sql` | SQL | Creates `clinical.vPatientChart` and its supporting chart views. |
| `04-procedures.sql` | SQL | Creates the eleven read/write procedures (admit, discharge, record vitals, place order, file lab, add note/diagnosis/allergy, `SearchEncounters`, chart reads). `SearchEncounters` supports optional ID, date, status, unit, department, and provider-name filters and returns readable encounter summaries. They are the hospital's contract, not this project's app's: the same procedures are what Data API Builder and the agent expose in Agentic AI. |
| `05-seed.sql` | SQL | Seeds the database to roughly **12 GB** of fully synthetic data (Observation is the ~108M-row anchor). Runs ~5–15 min — log-rate gated. |
| `verify-data.sql` | SQL | Read-only PASS/FAIL check with per-table volume checks. You want it to end with **`ALL CHECKS PASSED`**. |
| `add-replicas.ps1` | PowerShell | Adds a second **HA replica**, then creates the **`wardgeneral-research`** named replica (serverless `HS_S_Gen5_8`) and prints the resulting topology. A named replica is read-only, looks like a separate database, and is **not** a failover target. Architecture dissects it; AI-Ready SQL uses it. |

## Deploy inputs (environment variables)

`provision-hyperscale.ps1` reads its inputs from environment variables, each with
a sensible default. Set any overrides **before** running it (the
`deploy-hyperscale` skill sets these for you during the guided deploy):

| Variable | Default | Notes |
|---|---|---|
| `LOC` | `eastus2` | Region — pick one with availability-zone support and `HS_Gen5` quota. |
| `RG` | `rg-collierhealth` | Resource group. |
| `SRV` | `collierhealth-<random>` | Logical server — must be globally unique. |
| `DB` | `wardgeneral` | The Hyperscale database. |
| `SLO` | `HS_Gen5_8` | Compute shape — changeable later. |
| `HA_REPLICAS` | `1` | Required for zone redundancy. |
| `ADMIN_OBJECT_ID` | *(required)* | Entra object ID for the server's Entra admin. |
| `ADMIN_DISPLAY_NAME` | `Collier Health DBAs` | Entra admin display name. |
| `ADMIN_TYPE` | `Group` | `User` \| `Group` \| `ServicePrincipal`. |
| `SQL_ADMIN_USER` | `wardadmin` | Mixed-auth SQL admin login (Security moves to Entra-only). |
| `SQL_ADMIN_PASSWORD` | *(required)* | Set in the environment — never hard-coded. |

## Running the SQL scripts (and re-running them)

Run `01`→`05` **in order once**, then `verify-data.sql`. **You never drop the
database to start over:**

- **Reload just the data** → re-run `05-seed.sql` alone (truncate + reseed).
- **Rebuild after a schema change** → re-run `02`→`05` (`02` drops and recreates
  the tables, discarding data).
- `01` is a guarded no-op; `03`/`04` are `CREATE OR ALTER` (safe anytime).

### If you have already deployed the AI-Ready SQL scripts

Only relevant on a **second** run of `05-seed.sql`, and only if you have been
through AI-Ready SQL. Two AI-Ready SQL tables take a foreign key into data this seed
owns — `clinical.ClinicalNoteEmbeddings` on `ClinicalNote`, and
`clinical.AIAssistanceLog` on `Encounter` — and a foreign key blocks `TRUNCATE`
outright, whether or not the child holds a single row. So the seed **drops both**
before it reloads. On a first run neither exists and both drops are no-ops.

`clinical.AIAssistanceLog` has to be dropped rather than emptied. AI-Ready SQL
creates it as an **append-only ledger table** for the tamper-evident audit trail,
and an append-only ledger table supports neither `DELETE` nor `TRUNCATE` — see
[Ledger considerations and limitations](https://learn.microsoft.com/sql/relational-databases/security/ledger/ledger-limits),
items 3 and 4. `DROP` is the only route that works.

Dropping a ledger table is a **soft delete by design**. The object is renamed to
`MSSQL_DroppedLedgerTable_*` and physically retained so the ledger digest stays
verifiable ([DROP TABLE, Remarks](https://learn.microsoft.com/sql/t-sql/statements/drop-table-transact-sql#remarks)).
Every reseed leaves one more of these behind, and **they are supposed to stay** —
that is the cost of a tamper-evident trail, not a leak. Leave them alone.

So after re-running `05-seed.sql`, redeploy AI-Ready SQL: `06-ai-embeddings.sql`,
`07-vector-index.sql`, `08-ai-assistance.sql`. The Ward General App app runs fine
without them so long as the `AiAssistance` feature flag is off.

Every `.sql` file opens with the seven-line `SET`-options preamble so the scripts
behave identically in the MSSQL extension, SSMS, or `sqlcmd`. See the
[repository README](../../README.md) for the full re-run and `SET`-options
explanation.

## A note on the data

**All data is synthetic. There is no real patient data (PHI) here — ever.** The
dataset was generated with AI assistance and, while plausible, may not accurately
represent real medical, clinical, laboratory, or billing data. It is for
educational and illustrative purposes only and must not be used for clinical,
diagnostic, or any real-world healthcare decision-making.
