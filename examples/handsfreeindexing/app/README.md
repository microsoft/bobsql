# Caldova Patient Access Operations

A .NET 10 Blazor Server application for the live Azure SQL hands-free indexing lifecycle.

- **Operations Dashboard** executes `demo.usp_PatientAccessDashboard` and records duration and logical reads.
- **Index Health** reads persisted live telemetry for the current NCI and provides playback controls for captured history.
- A background service pairs dashboard measurements with physical samples while compaction is running.
- The app does not create indexes, generate bloat, enable AIC, force plans, or load recorded calibration data.
- `/healthz` reports process health.
- `/readyz` reports whether the configured SQL database and demo schema are ready.

Set `ConnectionStrings__Caldova` for local development, then run:

```powershell
dotnet run --project ./CaldovaPatientAccessOps.csproj
```

## Local Azure SQL container

> [!WARNING]
> **Under construction:** the local connection and manual index baseline work,
> but the bloat and automatic index compaction lifecycle is not yet complete.
> These instructions are preparation notes, not a finished local demo.

The `local-container` launch profile runs at `http://localhost:5181` and labels the
app **Local Azure SQL container - localhost,14332**. It uses the same live SQL
service and telemetry as Azure deployment; there is no offline replay data.

Initialize a dedicated database such as `caldova-hfi-local` by running
`../00-setup.sql` against `localhost,14332` using an administrator connection.
This script resets the demo schema and loads two million rows, so do not run it
against a database containing a demo you want to preserve. The container must
pass the setup script's Hyperscale check and support automatic tuning and AIC.
Standard SQL Server containers are not a substitute.

Create a contained SQL user for the app in that database, granting the same six
procedure-level `EXECUTE` permissions listed in `../07-grant-app-identity.sql`
(use SQL authentication instead of that file's external-identity creation).
Store its connection string in development user secrets, not a tracked settings
file. From this directory:

```powershell
$credential = Get-Credential -UserName 'caldova_app' -Message 'Local demo database user'
$connection = [System.Data.Common.DbConnectionStringBuilder]::new()
$connection['Server'] = 'localhost,14332'
$connection['Database'] = 'caldova-hfi-local'
$connection['User ID'] = $credential.UserName
$connection['Password'] = $credential.GetNetworkCredential().Password
$connection['Encrypt'] = 'True'
$connection['TrustServerCertificate'] = 'True' # local development certificate only
@{ 'ConnectionStrings:Caldova' = $connection.ConnectionString } |
    ConvertTo-Json -Compress | dotnet user-secrets set
$connection.Clear()
Remove-Variable credential, connection
dotnet run --launch-profile local-container
```

User secrets are local development storage, not an encrypted production vault.
An existing `ConnectionStrings__Caldova` environment variable overrides them;
remove that override before using this profile if it points elsewhere.

For lifecycle preparation, run the numbered SQL files directly against the local
database with your administrator connection. The `deploy/` lifecycle wrappers
still target Azure and require Azure CLI configuration. Automatic index creation
can take hours: verify `auto_created = 1` with `02-check-auto-index.sql` before
running bloat or compaction. An accepted `CREATE_INDEX = ON` setting alone does
not prove that the local container's automatic tuning service creates indexes.
For a local container without automatic index creation, explicitly create the
equivalent covering index using an administrator connection:

```sql
IF DB_NAME() <> N'caldova-hfi-local'
    THROW 50071, 'Manual index creation is restricted to the isolated local demo database.', 1;

CREATE NONCLUSTERED INDEX IX_PatientAccessActivity_LocalDashboard
ON demo.PatientAccessActivity (ServiceRegionId, ActivityAt)
INCLUDE (AppointmentStatus, SpecialtyCode, WaitMinutes, PatientInstructions, RevisionNumber);
```

Run this once, then refresh the Operations Dashboard to capture a paired indexed
baseline. Index Health displays **Healthy Indexed Baseline** and labels this index
**(manual)** with `auto_created = 0`. This is not a demonstration of automatic
index creation. The Azure lifecycle scripts retain their `auto_created = 1`
guards, so the existing bloat and compaction scripts reject this manual index.
Compaction recovery must still be measured before claiming it occurred locally.
