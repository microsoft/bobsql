# Observability — Monitor Engine Health with Extended Events

This workflow creates a bounded, database-scoped `wardgeneral_health` session
for current engine-health evidence. It captures severity-16+ system errors,
database deadlocks, and client attentions in a volatile ring buffer.

> **New here?** Read the [engine-events README](../README.md) first. Configure
> the server and database in
> [`../../../first-app/wardgeneral.env`](../../../first-app/wardgeneral.env.template).

## Workflow

1. Create or start the idempotent session:

   ```powershell
   ./observability/engineevents/xevent/setup-xevent-health.ps1
   ```

2. Optionally run `test-xevent-health.sql` once against `wardgeneral`. Its
   nonexistent table reference raises expected system error 208 and changes no
   data or schema.

3. Run `read-xevent-health.sql` against `wardgeneral` to inspect target counts,
   drops, truncation, and captured rows.

4. Leave the session running for the lab. To remove it, preview and approve the
   teardown:

   ```powershell
   ./observability/engineevents/xevent/teardown-xevent-health.ps1 -WhatIf
   ./observability/engineevents/xevent/teardown-xevent-health.ps1
   ```

Dropping the session discards its ring buffer. The target is capped at 1 MB and
1,000 events and can lose events under pressure. Use an Azure Blob `event_file`
target when evidence must be durable.

## Captured events

| Event | Purpose |
| --- | --- |
| `sqlserver.error_reported` | System errors with severity 16 or higher; user-defined errors are excluded. |
| `sqlserver.database_xml_deadlock_report` | Database-scoped deadlock graphs. |
| `sqlserver.attention` | Client cancellations, timeouts, or broken connections. |

## Files

| File | Purpose |
| --- | --- |
| `setup-xevent-health.ps1` | Loads configuration and invokes the idempotent setup SQL. |
| `setup-xevent-health.sql` | Defines and starts `wardgeneral_health`. |
| `test-xevent-health.sql` | Generates controlled system error 208. |
| `read-xevent-health.sql` | Reads ring-buffer counters and events. |
| `teardown-xevent-health.ps1` | Previews and confirms session removal. |
| `teardown-xevent-health.sql` | Stops and drops only `wardgeneral_health`. |

## Sources

- [Microsoft Learn — Extended Events in Azure SQL](https://learn.microsoft.com/azure/azure-sql/database/xevent-db-diff-from-svr), accessed 2026-09-01
- [Microsoft Learn — Extended Events ring buffer target](https://learn.microsoft.com/sql/relational-databases/extended-events/targets-for-extended-events-in-sql-server#ring_buffer-target), accessed 2026-09-01
