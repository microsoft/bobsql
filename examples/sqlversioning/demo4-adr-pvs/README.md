# Demo 4 — ADR & PVS

ADR versioning internals: in-row vs off-row version storage, PVS Cleaner deep dive, watermark pinning diagnostics, and instant rollback comparison.

## Scripts

| Script | Session | Purpose |
|--------|---------|---------|
| `demo4a-adr-versioning-session1.sql` | Session 1 (Reader) | ADR ON/RCSI OFF blocks → enable RCSI, in-row version proof |
| `demo4a-adr-versioning-session2.sql` | Session 2 (Writer) | Three UPDATEs with PVS DMV queries after each |
| `demo4b-adr-offrow-versioning-session1.sql` | Session 1 (Reader) | Off-row: wide CHAR(600) column, PVS size non-zero |
| `demo4b-adr-offrow-versioning-session2.sql` | Session 2 (Writer) | Single wide UPDATE, off-row from the start |
| `demo4c-pvs-cleaner-deep-dive.sql` | Session 1 | PVS Cleaner: async background timer, page-level cleanup |
| `demo4c-session2.sql` | Session 2 | Snapshot in another DB blocks cleanup via global XTS |
| `demo4d-pvs-watermark-pinning.sql` | Single session | Cross-table pinning, skip reasons, idle connection diagnostics |
| `demo4e-adr-recovery.sql` | Single session | Large transaction rollback: traditional vs ADR near-instant |

## Key Concepts

- **ADR and RCSI are independent flags** — ADR provides the PVS infrastructure, RCSI flips scan behavior from locking to versioning
- **In-row versioning**: small diffs stored directly on the data page (e.g., narrow Balance update)
- **Off-row versioning**: full before-image written to a dedicated PVS page (e.g., wide CHAR(600) update)

## Dependencies

### Python Packages

```
pip install flask mssql-python
```

### ADR DBCC PAGE Viewer

Start before demo4a/4b:

```
python dbcc_page_viewer_adr.py
# Open http://localhost:5051
```

## How to Run

For multi-session scripts, open each `-session1` / `-session2` file in a separate SSMS window and follow the `>>> Go to Session N` cues.
