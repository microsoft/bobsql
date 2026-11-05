---
name: tempdb-growth
description: "Diagnose unexpected tempdb data-file or transaction-log growth on SQL Server and Azure SQL Managed Instance. Use for tempdb filling up, space pressure, temporary object allocation, spills, version-store retention, long transactions, or growth during slow workloads, using troubleshoot/tempdb."
---

# Diagnose unexpected tempdb growth

## Procedure

1. Read the [diagnostic guide](../../../troubleshoot/tempdb/growth-and-slow-workloads/readme.md).
   Confirm SQL Server 2019+ or Azure SQL Managed Instance, the intended instance,
   permissions, incident timeline, and whether data or log growth is reported.
   This kit does not support Azure SQL Database, Synapse, or Fabric. Do not run
   these scripts against those products or improvise around a platform guard.
2. Obtain an approved connection to `tempdb`. Read scripts before execution.
   Use the existing SQL connection/tool or SSMS/sqlcmd; never invent credentials,
   targets, or results. All diagnostics are read-only, but may require elevated
   monitoring permissions and add some load.
3. Run [space and IO](../../../troubleshoot/tempdb/growth-and-slow-workloads/01-space.sql)
   first. Separate allocated file size, occupied categories, reusable extent
   space, and log occupancy. Free extents do not measure free disk capacity.
4. Run [consumers](../../../troubleshoot/tempdb/growth-and-slow-workloads/02-consumers.sql)
   to identify session allocations, active requests, and blocking. Keep SQL text
   disabled unless explicitly approved for a private capture. Session and request
   results overlap; never add those result sets together.
5. For log pressure, run [log transactions](../../../troubleshoot/tempdb/growth-and-slow-workloads/03-log-transactions.sql).
   Examine reuse waits, transaction age, used/reserved log bytes, and owners.
   A sleeping session with an open transaction can matter; the biggest writer
   is not necessarily the oldest transaction preventing reuse.
6. For version retention, run [version stores](../../../troubleshoot/tempdb/growth-and-slow-workloads/04-version-store.sql).
   Distinguish traditional tempdb versions from ADR persistent versions. PVS in a
   user database is not tempdb occupancy; SQL Server 2025 can also enable ADR/PVS
   in tempdb. Long-lived snapshot transactions are candidates, not proven blockers
   of cleanup. Account for database visibility and readable-secondary retention.
7. Repeat relevant scripts at a modest interval (for example 30-60 seconds) and
   compare timestamps, file sizes, allocations, progress, and IO counter deltas.
   Discard deltas across restarts or counter resets; session IDs can be reused.
   Stop on errors and report the failing script and permission/platform issue.
   Do not present partial or permission-limited results as a clean bill of health.
8. Report observed data/log growth, dominant category, likely owners, progress or
   waits, measured evidence, remaining hypotheses, and a safe next action.
   Request approval before shrink, restart, kill, configuration changes, or
   workload replay. Recommend one evidence-supported change and verify it with
   comparable samples; successful space reuse does not require file shrink.

If no approved connection is available, provide the execution order and request
redacted results rather than claiming a diagnosis. Do not save raw query text,
production captures, or credentials in this public repository. Follow
[secret handling](../../../SECRET-SCANNING.md).
