# Observability — Monitor and Troubleshoot Connections

This read-only workflow uses two Azure SQL Database views in the logical
server's `master` database. `sys.event_log` supplies event detail;
`sys.database_connection_stats` summarizes connection successes and failures.

> **Requirement:** The caller must have access to the logical server's `master`
> database. These views cannot be queried from a user database. The script
> explicitly connects to `master` and returns every database visible to the
> caller; it does not filter to `wardgeneral`.

## Run the queries

To run the queries ad hoc, connect the MSSQL extension or SSMS directly to the
logical server's `master` database and execute `connection-history.sql`. Its
first two declarations set the 24-hour lookback and 200-row event limit; edit
those values when another bounded window is needed.

To let PowerShell load `wardgeneral.env`, resolve the new sqlcmd, and connect to
`master`, run from the repository root:

```powershell
./observability/engineevents/connections/run-connection-history.ps1
```

The default lookback is 24 hours and detailed events are capped at 200 rows.
Both limits are configurable:

```powershell
./observability/engineevents/connections/run-connection-history.ps1 `
  -Hours 72 `
  -EventLimit 500
```

The wrapper uses passwordless Entra authentication and always passes `-d master`
and `-i connection-history.sql`. Azure SQL Database does not support switching
to `master` with a `USE` statement from an existing user-database connection.
For non-default limits, the wrapper writes a parameterized temporary copy of the
same SQL file, invokes it with `-i`, and removes it in a `finally` block.

## When to use each view

| View | Use it for | What it does not tell you |
| --- | --- | --- |
| `sys.event_log` | Investigating the type and reason for individual or aggregated connectivity events. It distinguishes successful connections, login failures, firewall blocks, terminated connections, throttling, deadlocks, and the other event types documented for the view. Use its subtype and description when a connection trend needs explanation. | It is not a complete SQL error log or application exception stream. It includes only documented event types and can omit telemetry. |
| `sys.database_connection_stats` | Establishing a compact five-minute time series of successful and failed connections per database. Use it to identify when connection success changed and which intervals deserve detail from `sys.event_log`. | It does not explain failure subtypes. `terminated_connection_count` and `throttled_connection_count` are documented as unused and must not be interpreted. |

Use `sys.database_connection_stats` first for the timeline, then correlate an
interesting database and UTC interval with `sys.event_log` for detail.

## File

| File | Purpose |
| --- | --- |
| `connection-history.sql` | Ad-hoc, read-only queries for `sys.event_log` detail and `sys.database_connection_stats` counts across all visible databases. Run against `master`. |
| `run-connection-history.ps1` | Loads configuration and invokes `connection-history.sql` through the new sqlcmd with `-d master -i`. |

Both views use five-minute UTC intervals for aggregated connectivity events.
Data usually accumulates within an hour but can take up to 24 hours to appear.
Retention is at most 30 days and can be shorter. The views are not lossless:
they expose only documented event types, and some telemetry can be missing.

`additional_data`, `terminated_connection_count`, and
`throttled_connection_count` are retained for backward compatibility and are
currently unused. Do not interpret their null or zero values as additional
connection evidence.

## Sources

Microsoft Learn, accessed 2026-09-01:

- [`sys.event_log`](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-event-log-azure-sql-database)
- [`sys.database_connection_stats`](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-database-connection-stats-azure-sql-database)
