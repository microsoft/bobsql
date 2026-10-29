# High Availability and Resiliency — Recover Ward General with Point-in-Time Restore

This demonstration captures the current Ward General database as of an exact
server-generated UTC time and restores that point into a lower-compute
Hyperscale serverless database for isolated testing. The source database
remains online and is not overwritten.

## Files

| File | Purpose |
| --- | --- |
| `prepare-pitr.ps1` | Captures an exact current-as-of-start UTC restore point from the source database. |
| `prepare-recovery-point.sql` | Returns the source database's `SYSUTCDATETIME()` without changing data. |
| `pitr-restore.ps1` | Previews the exact restore; `-Execute` asynchronously submits creation of a low-compute Hyperscale serverless test database. |
| `show-operation-status.ps1` | Polls `master.sys.dm_operation_status` until the restored database's management operation completes or reaches a bounded timeout. |
| `operation-status.sql` | Returns structured restore operation state, percentage, errors, and UTC timestamps retained for approximately one hour. |
| `verify-pitr.ps1` | Validates the restored resource and runs Getting Started's Ward General schema and data checks against it. |
| `cleanup-pitr.ps1` | Previews cleanup; `-Execute` deletes only the named restored test database. |

## Prerequisites

- Complete the Getting Started `wardgeneral` deployment.
- Configure Ward General App's `wardgeneral.env` or set `WardGeneral__Server` and
   `WardGeneral__Database`.
- Sign in with `az login` and select the subscription containing the database.
- Install the new Go-based `sqlcmd` and verify `sqlcmd --version` succeeds.

## Run the demonstration

Capture and preserve the printed `RestorePointUtc`:

```powershell
./ha-resiliency/pitr/prepare-pitr.ps1
```

Preview the billable restore using those exact values:

```powershell
./ha-resiliency/pitr/pitr-restore.ps1 `
   -RestorePointUtc '<RestorePointUtc>' `
   -RestoredDatabase 'wardgeneral-pitr-demo'
```

After approval, rerun the same command with `-Execute`. It submits the restore
with `--no-wait` so the management operation can be observed while it runs.
Point-in-time restore always creates a new database and can take several
minutes. If Azure reports that the exact point is too recent, preserve the
values and rerun the same restore later. The copy remains current as of the
captured demo-start time; Azure does not expose the latest log backup point for
the script to discover.

The target defaults to `HS_S_Gen5_8` with a 1-vCore minimum, so it autoscales
between 1 and 8 vCores. Hyperscale serverless does not auto-pause. This test
copy intentionally does not reproduce the source database's provisioned
compute, HA replica count, zone redundancy, or named replicas. Those are
target-resource choices rather than recovered database state.

After submission, inspect its management-operation record:

```powershell
./ha-resiliency/pitr/show-operation-status.ps1 `
   -RestoredDatabase 'wardgeneral-pitr-demo'
```

Run this immediately after submitting the restore. The DMV is available only
in `master` to the server-level principal. The script polls every 15 seconds
for at most 60 minutes, reports state and `percent_complete`, stops immediately
on `FAILED` or `CANCELLED`, and returns only after `COMPLETED`. The completed
row supplies the restore duration from `start_time` to `last_modify_time`. It
confirms the management operation but does not replace the data verification.
Leave this command running in a foreground synchronous terminal until it
returns. Do not interrupt it, detach it through a shorter-lived execution
helper, or place it behind a terminal timeout shorter than 65 minutes.

Verify both sides:

```powershell
./ha-resiliency/pitr/verify-pitr.ps1 `
   -RestoredDatabase 'wardgeneral-pitr-demo'
```

The command passes only when Azure reports an online Hyperscale serverless
database and the existing Getting Started schema, volume, and coherence checks pass
against it. Azure can return a null `sourceDatabaseId` after PITR completes;
in that case the completed restore-operation row and the data checks are the
recovery evidence. A conflicting non-null source ID still fails verification.
Then preview cleanup:

```powershell
./ha-resiliency/pitr/cleanup-pitr.ps1 `
   -RestoredDatabase 'wardgeneral-pitr-demo'
```

After approval, rerun cleanup with `-Execute`.

## Boundaries

- Capturing the restore point is read-only; the example never updates source
   data.
- Restore and cleanup preview by default.
- The restore creates a billable Hyperscale serverless database and requires
   explicit approval. Serverless reduces idle compute to its configured floor;
   it does not eliminate compute or storage charges.
- Cleanup accepts only restored database names beginning with
   `wardgeneral-pitr-`.
- Preserve the exact `RestorePointUtc` for the entire workflow.

## Status

A live Azure restore completed and passed the full Ward General resource and
data verification on 2026-09-07. The restored test database was retained for
testing rather than cleaned up.

Reference: [Microsoft Learn — Restore a database from a backup](https://learn.microsoft.com/azure/azure-sql/database/recovery-using-backups#point-in-time-restore),
accessed 2026-09-06.

Reference: [Microsoft Learn — Create and configure a serverless database](https://learn.microsoft.com/azure/azure-sql/database/serverless-tier-create-configure),
accessed 2026-09-07.

Reference: [Microsoft Learn — sys.dm_operation_status](https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-objects/sys-dm-operation-status-azure-sql-database),
accessed 2026-09-06.
