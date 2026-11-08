---
name: sql-versioning
description: "Run the SQLBits 2026 SQL Server versioning demos: blocking, RCSI versus Snapshot, update conflicts, version chains, ADR/PVS cleanup, optimized locking, and benchmark comparisons. Use when working with examples/sqlversioning. For the local browser click-through apps, also load sql-versioning-apps."
---

# SQL Server versioning explained

For browser-based demos 0-4, load the
[sql-versioning-apps skill](../sql-versioning-apps/SKILL.md). In this repository,
"run the app" means verify/start the backend and open a new normal external
browser window, not the VS Code integrated browser.

## Procedure

1. Read the [demo inventory](../../../examples/sqlversioning/README.md).
   Work from `examples/sqlversioning`; the descriptive demo folders retain
   their numeric prefixes. Use the inventory's current paths.
2. Verify SQL Server 2025 and permissions. Inspect `demo0-setup/demo0-setup.sql`
   for database names/data creation and get approval before executing.
   Run `tools/check-readiness.ps1` with reviewed targets before the session.
3. Choose the desired concept and open `session1`/`session2` scripts in
   separate SSMS windows. Follow their handoff cues; do not batch-run both
   sides or leave snapshot transactions open between demonstrations.
4. For DBCC PAGE viewers, inspect the viewer source/configuration, confirm
   Python dependencies, and start only the required local viewer. Preserve
   autocommit behavior so diagnostic connections do not pin version cleanup.
5. Verify the intended evidence: blocking versus consistent reads, conflict
   errors, version-chain structure, PVS cleanup, or lock counts. Internal page
   formats and cleanup timing are not stable production contracts.
6. For throughput tests, read the
   [benchmark guide](../../../examples/sqlversioning/benchmark/README.md),
   verify `sqlsim`, approve database creation/load, and preserve comparable
   configurations. Do not quote captured numbers as new measurements.
7. Close all transactions, stop viewers/drivers by their specific process IDs,
   and confirm lab state before any requested cleanup.

Follow [secret checks](../../../SECRET-SCANNING.md); do not publish private
connection details in viewer configuration or result files.
