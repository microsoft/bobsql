# Observability — Retain Azure SQL Errors

This workflow routes Azure SQL Database `Errors` resource logs to a dedicated
Log Analytics workspace, generates one controlled error, queries the
resource-specific `AzureSQLErrors` table, and removes only the resources this
example owns.

> **New here?** Read the [engine-events README](../README.md) first. Configure
> the server and database in
> [`../../../first-app/wardgeneral.env`](../../../first-app/wardgeneral.env.template).

## Cost and safety

Setup enables billable Log Analytics ingestion and retention. Use it only in a
learning environment. Run setup and teardown with `-WhatIf` first. Workspace
deletion is recoverable unless `-PermanentlyDelete` is explicitly supplied.

## Workflow

1. Preview and approve setup:

   ```powershell
   ./observability/engineevents/azuresqlerrors/setup-azuresqlerrors.ps1 -WhatIf
   ./observability/engineevents/azuresqlerrors/setup-azuresqlerrors.ps1
   ```

2. Generate one controlled error. Use either error 50001:

   ```text
   azuresqlerrors/generate-azuresqlerror.sql
   ```

   Or use the misspelled `clinical.Observaton` reference to generate system
   error 208:

   ```text
   azuresqlerrors/generate-object-not-found.sql
   ```

   Run the selected SQL file once against `wardgeneral`. A nonzero client exit
   is expected. Neither script changes data or schema.

3. Query retained rows:

   ```powershell
   ./observability/engineevents/azuresqlerrors/azuresqlerrors.ps1
   ```

   Delivery is asynchronous. A qualifying event can take time to appear, and
   the telemetry path can throttle. No rows does not prove that the application
   saw no errors.

4. Preview and approve teardown when the retained evidence is no longer needed:

   ```powershell
   ./observability/engineevents/azuresqlerrors/teardown-azuresqlerrors.ps1 -WhatIf
   ./observability/engineevents/azuresqlerrors/teardown-azuresqlerrors.ps1
   ```

## Files

| File | Purpose |
| --- | --- |
| `setup-azuresqlerrors.ps1` | Creates the tagged workspace and resource-specific `Errors` route. |
| `generate-azuresqlerror.sql` | Raises controlled user error 50001. |
| `generate-object-not-found.sql` | Raises system error 208 through a misspelled table name. |
| `azuresqlerrors.ps1` | Queries retained `AzureSQLErrors` rows read-only. |
| `teardown-azuresqlerrors.ps1` | Removes the owned diagnostic setting and workspace with safeguards. |

## Source

- [Microsoft Learn — AzureSQLErrors](https://learn.microsoft.com/azure/azure-monitor/reference/tables/azuresqlerrors), accessed 2026-09-01
