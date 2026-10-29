# Observability — Diagnose Engine Events

Azure SQL Database does not expose the underlying SQL Server `ERRORLOG`, and no
single Azure surface replaces it. This folder starts with retained database
error events in Azure Monitor Logs.

Choose the evidence surface that matches the question:

| Folder | Question |
| --- | --- |
| [`azuresqlerrors/`](azuresqlerrors/) | Which qualifying Azure SQL errors were retained in Log Analytics? |
| [`xevent/`](xevent/) | Which current errors, deadlocks, and attentions are in the bounded health-session ring buffer? |
| [`connections/`](connections/) | What connection events and five-minute connection counts are visible from `master`? |

> **New here?** Read the [repository README](../../../README.md) first. These
> scripts use the server and database already configured in
> [`../../first-app/wardgeneral.env`](../../first-app/wardgeneral.env.template).

## Files

| File | Purpose |
| --- | --- |
| `azuresqlerrors/README.md` | Retained-error setup, query, and teardown workflow. |
| `azuresqlerrors/setup-azuresqlerrors.ps1` | Creates the dedicated, tagged Log Analytics workspace and the database diagnostic setting that routes `Errors` using the resource-specific schema. |
| `azuresqlerrors/generate-azuresqlerror.sql` | Raises one controlled error 50001 with a recognizable marker. It changes no data or schema. |
| `azuresqlerrors/generate-object-not-found.sql` | Queries a deliberately misspelled Ward General table to raise system error 208. It changes no data or schema. |
| `azuresqlerrors/azuresqlerrors.ps1` | Resolves the configured Azure SQL database, discovers its Log Analytics workspace, queries `AzureSQLErrors`, and displays retained error events. |
| `azuresqlerrors/teardown-azuresqlerrors.ps1` | Removes the Observability diagnostic setting and dedicated Log Analytics workspace, with confirmation and ownership checks. |
| `xevent/setup-xevent-health.ps1` | Loads the shared configuration and creates or starts `wardgeneral_health` through the new sqlcmd. |
| `xevent/setup-xevent-health.sql` | Defines the bounded, database-scoped `wardgeneral_health` Extended Events session with `STARTUP_STATE=ON`. |
| `xevent/read-xevent-health.sql` | Reads ring-buffer metadata and renders captured errors, deadlocks, and attentions as rows. |
| `xevent/test-xevent-health.sql` | Raises system error 208 through an invalid object reference. It changes no data or schema. |
| `xevent/teardown-xevent-health.ps1` | Confirms before stopping and dropping `wardgeneral_health`; supports `-WhatIf`. |
| `xevent/teardown-xevent-health.sql` | Stops and drops `wardgeneral_health`, discarding its volatile ring-buffer contents. |
| `xevent/README.md` | Bounded Extended Events health-session workflow. |
| `connections/README.md` | Read-only connection monitoring and troubleshooting workflow. |
| `connections/connection-history.sql` | Ad-hoc query for both connection-history views; must run in `master`. |
| `connections/run-connection-history.ps1` | Connects to `master` and invokes the connection-history SQL for all visible databases. |

## Cost and impact warning

A Log Analytics workspace and diagnostic setting must exist before
`AzureSQLErrors` can retain anything. Creating that path enables billable log
ingestion and retention. An active or error-heavy database can ingest more data
than an idle lab database. The setup belongs only in a learning environment;
do not enable it against production merely to run this example.

The consumer script is read-only. Teardown is destructive: it stops future log
collection, removes the queryable workspace, and can permanently discard its
retained evidence. Review the workspace carefully before approving deletion.

## Set up error collection

Start with a dry run:

```powershell
./observability/engineevents/azuresqlerrors/setup-azuresqlerrors.ps1 -WhatIf
```

Then run without `-WhatIf` and approve the workspace and diagnostic-setting
operations:

```powershell
./observability/engineevents/azuresqlerrors/setup-azuresqlerrors.ps1
```

The setup is idempotent. It creates `wardgeneral-observability-logs` by default with
30-day retention and the ownership tag `wardgeneral=observability-engineevents`. It
creates only the `observability-azuresqlerrors` diagnostic setting on the configured
database, sets `logAnalyticsDestinationType=Dedicated`, and enables only the
`Errors` category. It refuses to reuse an
existing untagged workspace or a same-named diagnostic setting that points
somewhere else.

Log delivery is asynchronous. Events generated before the diagnostic setting
exists are not backfilled.

After setup, run `generate-azuresqlerror.sql` once against `wardgeneral` with
the MSSQL extension, SSMS, or the new sqlcmd. The expected result is error
50001 with marker `CH07_ENGINEEVENTS_AZURESQLERRORS_TEST`. The error is
intentional and changes no data or schema. Allow for ingestion delay before
querying the workspace.

To test a familiar system error instead, run
`azuresqlerrors/generate-object-not-found.sql` once. Its deliberately
misspelled `clinical.Observaton` reference raises error 208, severity 16. A
nonzero client exit is expected; do not retry it.

## Query retained errors

From the repository root:

```powershell
./observability/engineevents/azuresqlerrors/azuresqlerrors.ps1
```

The default lookback is 24 hours. To use another interval:

```powershell
./observability/engineevents/azuresqlerrors/azuresqlerrors.ps1 -Hours 72
```

The script discovers a workspace from diagnostic settings on the configured
database or logical server. If discovery is not possible, pass the exact ARM
resource ID:

```powershell
./observability/engineevents/azuresqlerrors/azuresqlerrors.ps1 `
  -WorkspaceResourceId '<workspace-resource-id>'
```

`AzureSQLErrors` can return the UTC time, error number, severity, state,
user-defined flag, message, query hash, plan hash, and operation. Query and plan
hashes can connect retained errors back to Query Store when those fields are
available.

Current implementation source inspection on 2026-09-01 showed that the internal
Extended Events source captures `sqlserver.error_reported` when either:

- severity is 16 or higher; or
- the error number is 3257, 3999, 17803, 701, 802, 8645, 8651, 8657, or 8902.

The downstream diagnostic-log transformation then requires
`is_azure_connection = 1` and `database_id > 4`. In other words, the event must
be associated with an Azure/client connection and occur in a user database.
There is no additional error-number allowlist in that transformation. Emitted
rows use category `Errors` and operation `ErrorEvent`.

This normally includes severity-16 errors such as invalid object name (208),
conversion failure (245), constraint conflict (547), divide by zero (8134), and
`THROW` or `RAISERROR` at severity 16 or higher. It normally excludes syntax
error 102, permission error 229, duplicate-key errors 2601 and 2627, deadlock
victim error 1205, informational messages, system-database errors, and internal
errors with no associated Azure connection.

No rows means no retained rows matched the query. It does not prove that the
application saw no errors: severity 11–15 errors are generally outside this
dataset, and the telemetry path can throttle. Compare client-side SQL exception
telemetry when a complete application view is required. A qualifying controlled
error that does not appear should prompt checks for ingestion delay, diagnostic
routing, and telemetry loss.

The table also depends on routing schema. A resource-specific route can expose
`AzureSQLErrors`. A database-level `Errors` category using Azure Diagnostics
mode writes to `AzureDiagnostics` instead. The consumer fails clearly when
`AzureSQLErrors` is unavailable rather than silently querying the wrong schema.

## Tear down the workspace

Start with a dry run:

```powershell
./observability/engineevents/azuresqlerrors/teardown-azuresqlerrors.ps1 -WhatIf
```

Then run without `-WhatIf` and approve the two operations when prompted:

```powershell
./observability/engineevents/azuresqlerrors/teardown-azuresqlerrors.ps1
```

The script deletes only the diagnostic setting named `observability-azuresqlerrors` and
a workspace carrying the ownership tag `wardgeneral=observability-engineevents`.
Deletion is recoverable by default. To bypass the Azure recovery period and
release the workspace name immediately:

```powershell
./observability/engineevents/azuresqlerrors/teardown-azuresqlerrors.ps1 `
  -PermanentlyDelete
```

Permanent deletion cannot be undone. The script refuses to delete an untagged
workspace unless `-AllowUntaggedWorkspace` is supplied after its ownership has
been independently verified.

Other event classes have separate datasets, including timeouts, blocks,
deadlocks, Query Store runtime and wait statistics, database waits, and
automatic tuning. Performance decides which retained performance events support
its tuning scenarios.

## Run an always-on health session

Azure SQL Database exposes hundreds of Extended Events; live `wardgeneral`
reported 725 on the engine build tested for this area. A useful health
session should not collect all of them. `wardgeneral_health` captures three
low-volume signals that answer distinct operational questions:

| Event | Question |
| --- | --- |
| `error_reported` | Which system errors at severity 16 or higher reached this database? |
| `database_xml_deadlock_report` | Which sessions and resources formed a database deadlock? |
| `attention` | Which requests were canceled by a client, timed out, or lost their connection? |

The error predicate excludes user-defined errors. The session records client,
identity, session, query-hash, plan-hash, and SQL-text actions where the event
supports them. It uses `ON DATABASE`, because Azure SQL Database supports only
database-scoped sessions.

Create and start the session from the repository root:

```powershell
./observability/engineevents/xevent/setup-xevent-health.ps1
```

The wrapper loads `wardgeneral.env`, requires the new Go-based sqlcmd, and runs its
companion `setup-xevent-health.sql` against `wardgeneral` with passwordless
Entra authentication. The setup is idempotent. It leaves an existing session
unchanged and starts it only when it is stopped. `STARTUP_STATE=ON` starts it
again when the database comes online.

The target is deliberately bounded to 1 MB and 1,000 events. It allows a single
event to be lost rather than blocking the workload under pressure. This is an
always-running current-health window, not durable history: old events roll out,
the ring buffer is cleared when the session stops, and failover loses its
contents even though startup state starts a fresh session on the new compute.
Use an Azure Blob `event_file` target when the evidence must survive those
boundaries.

To prove the session without changing data or schema, run
`xevent/test-xevent-health.sql`. Error 208 is expected. Then run
`xevent/read-xevent-health.sql`. Its first result reports event count, dropped
count, XML truncation, and memory used. Its second result shows the newest
events first. `Truncated = 1` means the ring-buffer XML omitted data while being
materialized.

Leave the session running for the lab. When it must be removed, preview the
teardown first:

```powershell
./observability/engineevents/xevent/teardown-xevent-health.ps1 -WhatIf
```

Then run without `-WhatIf` and approve the operation:

```powershell
./observability/engineevents/xevent/teardown-xevent-health.ps1
```

Teardown stops and drops only `wardgeneral_health`; dropping it also discards
the ring-buffer evidence.

## Sources

Microsoft Learn, accessed 2026-09-01:

- [`AzureSQLErrors`](https://learn.microsoft.com/azure/azure-monitor/reference/tables/azuresqlerrors)
- [Configure streaming export of Azure SQL diagnostic telemetry](https://learn.microsoft.com/azure/azure-sql/database/metrics-diagnostic-telemetry-logging-streaming-export-configure)
- [Monitor Azure SQL Database](https://learn.microsoft.com/azure/azure-sql/database/monitoring-sql-database-azure-monitor)
- [Extended Events in Azure SQL](https://learn.microsoft.com/azure/azure-sql/database/xevent-db-diff-from-svr)
- [Extended Events ring buffer target](https://learn.microsoft.com/sql/relational-databases/extended-events/targets-for-extended-events-in-sql-server#ring_buffer-target)

The capture predicate and downstream transformation above were verified against
the current internal implementation source on 2026-09-01; Microsoft Learn does
not publish that implementation detail.
