# Tools — Diagnostic & Readiness Utilities

Pre-session validation and debugging tools for versioning demos.

## Readiness

| Script | Purpose |
|--------|---------|
| `check-readiness.ps1` | Pre-session validation: files, SQL connectivity, features, permissions |

## Diagnostics

| Script | Purpose |
|--------|---------|
| `pvs-cleanup-blocker.sql` | Finds active snapshots, open transactions, and idle sessions pinning PVS versions |
| `xevent-version-store-stats.sql` | XEvent session for `tx_version_additional_stats` (tempdb version store stats) |

## PVS Chain Debugging (Python)

| Script | Purpose |
|--------|---------|
| `diag_chain.py` | Chase PVS chain for AccountId 42 |
| `diag_page.py` | Dump DBCC PAGE output for AccountId 42 |
| `diag_pvs_all_slots.py` | Dump all slots on PVS page |
| `diag_pvs_chain.py` | Check PVS chain via `read_pvs_record` |
| `diag_pvs_full.py` | Full dump of PVS record(s) |
| `diag_pvs_offset.py` | Check offset 54 of PVS record |
| `diag_pvs_scan.py` | Scan all slots on PVS page to find V0 |
| `diag_vp.py` | Parse version pointer bytes |

## Scratch Files

| Script | Purpose |
|--------|---------|
| `_test_dbcc.sql` | Ad-hoc DBCC PAGE scratch file |
| `_test_slot41.py` | Ad-hoc hex dump parser for slot analysis |
