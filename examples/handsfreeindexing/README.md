# Caldova Hands-Free Indexing

A reproducible Azure SQL Database Hyperscale demo showing the complete lifecycle of one unchanged dashboard query:

1. The table starts without a useful nonclustered index.
2. Azure SQL automatic tuning creates a covering index (`auto_created = 1`).
3. Temporary insert/delete activity leaves that index sparse and slower.
4. Automatic Index Compaction repacks eligible leaf pages and restores performance.

The validated bloat workload uses four bounded insert/delete steps and the AIC
workload uses three 200,000-row insert/delete eligibility cycles. Surviving rows
are never updated. Progress capture uses `DETAILED` physical stats and pairs page
count and density with the latest dashboard duration and logical reads.

The app executes live SQL and reads persisted physical telemetry. It contains no recorded calibration frames, alternate baseline table, manual index fallback, forced plan, query hint, or synthetic delay.

## Prerequisites

- PowerShell 7
- Azure CLI authenticated to the target tenant
- [go-sqlcmd](https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-download-install) available as `sqlcmd`
- .NET 10 SDK
- Access to the Automatic Index Compaction preview

Set the required subscription and optional overrides:

```powershell
$env:AZURE_SUBSCRIPTION_ID = '<subscription-guid>'
$env:CALDOVA_RESOURCE_GROUP = 'rg-caldova-handsfree-indexing' # optional
$env:CALDOVA_SQL_LOCATION = 'eastus'                          # optional
$env:CALDOVA_APP_LOCATION = 'eastus2'                        # optional
$env:CALDOVA_SQL_VCORES = '4'                                # optional
```

Resource names are derived from the subscription ID unless overridden with `CALDOVA_SQL_SERVER`, `CALDOVA_DATABASE`, `CALDOVA_APP_PLAN`, or `CALDOVA_APP_NAME`.

All deployment and lifecycle PowerShell scripts dot-source `deploy/00-config.ps1`.
That file supplies the logical server and database to `go-sqlcmd`. Infrastructure
deployment also writes the same server/database into the App Service connection
string. The SQL files contain no logical-server or database names; they execute in
the database selected by the wrapper.

## Deploy

```powershell
./deploy/01-deploy-infrastructure.ps1
./deploy/02-initialize-database.ps1
./deploy/03-publish-app.ps1
./deploy/04-verify.ps1
```

Initialization creates two million rows, enables automatic index creation, disables automatic plan correction, and leaves `demo.PatientAccessActivity` with only its clustered primary key.

## Run the lifecycle

See [DEMO-RUNBOOK.md](DEMO-RUNBOOK.md) for the detailed gates.

```powershell
# Run this 15-minute interval repeatedly for several hours.
./deploy/05-run-workload.ps1

# Display the current missing-index recommendation without creating it.
./deploy/06-show-index-recommendation.ps1

# Check whether Azure automatic tuning created the index yet.
./deploy/07-check-auto-index.ps1

# After the check succeeds and reports auto_created = 1:
./deploy/08-create-bloat.ps1
./deploy/09-enable-compaction.ps1
./deploy/10-check-progress.ps1
```

Automatic tuning is asynchronous. Repeat `05-run-workload.ps1`, then run
`06-show-index-recommendation.ps1` and `07-check-auto-index.ps1`. Continue this cycle
for several hours until the check succeeds.

Run `10-check-progress.ps1` periodically while AIC is active. Refresh the Operations
Dashboard between physical captures so each Index Health frame pairs real query
duration and logical reads with real index state.

## Missing-index recommendation example

`01a-show-index-recommendation.sql` reads Azure SQL's missing-index DMVs and never
executes the generated statement. The current primary table already has its automatic
index, so the following representative output was captured from the equivalent
two-million-row no-index calibration copy after running the same query shape:

```text
schema_name:                    demo
table_name:                     PatientAccessActivityNoIndex
equality_columns:               NULL
inequality_columns:             [ServiceRegionId], [ActivityAt]
included_columns:               NULL
user_seeks:                     95
user_scans:                     0
average_user_impact_percent:    94.22
estimated_improvement:          207078.86
create_index_example:           CREATE INDEX [IX_Recommended_PatientAccessActivityNoIndex]
								ON [demo].[PatientAccessActivityNoIndex]
								([ServiceRegionId], [ActivityAt]);
```

On a freshly deployed user database, the script targets
`demo.PatientAccessActivity`; exact columns and impact values can evolve as the DMV
accumulates workload evidence. The script is evidence only. Azure automatic tuning,
not the script, creates the demo index.

## Remove resources

```powershell
./deploy/99-remove.ps1
```

This deletes the dedicated resource group and requires explicit confirmation.
