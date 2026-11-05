# SQL Server Versioning Explained — Demo Scripts

**Session**: SQLBits 2026  
**Speaker**: Bob Ward  
**Format**: 50-minute session (core demos) or 75-minute extended  

## Quick Start

1. Start SQL Server 2025 (local instance)
2. Run `demo0/demo0-setup.sql` in SSMS (creates 3 databases + seed data)
3. Run `tools/check-readiness.ps1` to verify everything is ready
4. Open each demo's session files in separate SSMS windows

## Databases

| Database | Purpose |
|----------|---------|
| `texasrangerswillwinitthisyear` | Primary demo database — Accounts, Orders, BigTable, BenchAccounts |
| `eaglesdontfly` | Cross-database demo — version store / PVS isolation tests (demo3b, demo4c) |
| `howboutthemcowboys` | Victim database — innocent OLTP impacted by cross-DB version bloat (demo3b) |

## Demo Flow (50-minute session)

| Order | Demo | Script(s) | What It Proves |
|-------|------|-----------|---------------|
| 1 | Setup | `demo0/demo0-setup.sql` | Creates databases, tables, seed data |
| 2 | RCSI vs Snapshot | `demo2/demo2b-*-session1.sql` + `session2.sql` | Statement-level vs transaction-level consistency |
| 3 | Version Chain | `demo3/demo3a-*-session1.sql` + `session2.sql` | DBCC PAGE proof of version records + chain building |
| 4 | Instance-Wide Impact | `demo3/demo3b-*-session1.sql` + `session2.sql` | Cross-database contamination via global XSN watermark |

Start the DBCC PAGE Viewer between demo2b and demo3a:
```
python demos/demo3/dbcc_page_viewer.py
# Open http://localhost:5050
```

## Full Demo Inventory

### Part 1 — Why Versioning?

| Script | Sessions | Purpose |
|--------|----------|---------|
| `demo1/demo1-blocking-session1.sql` | Session 1 (Writer) | X-lock blocks reader under READ COMMITTED; NOLOCK dirty read proof |
| `demo1/demo1-blocking-session2.sql` | Session 2 (Reader) | Blocked SELECT, NOLOCK read, clean read |

Proves the problem: readers block on writers without versioning.

### Part 2 — RCSI and Snapshot Isolation

| Script | Sessions | Purpose |
|--------|----------|---------|
| `demo2/demo2a-rcsi-session1.sql` | Session 1 (Writer) | Enable RCSI, hold X lock, commit |
| `demo2/demo2a-rcsi-session2.sql` | Session 2 (Reader) | RCSI non-blocking read; READCOMMITTEDLOCK opt-in blocking |
| `demo2/demo2b-rcsi-vs-snapshot-session1.sql` | Session 1 (Reader) | Two reads under RCSI (see change) vs Snapshot (frozen) |
| `demo2/demo2b-rcsi-vs-snapshot-session2.sql` | Session 2 (Writer) | UPDATE between reads (run twice — once per isolation level) |
| `demo2/demo2c-snapshot-conflict-session1.sql` | Session 1 (Snapshot Writer) | Open snapshot, attempt conflicting update → error 3960 |
| `demo2/demo2c-snapshot-conflict-session2.sql` | Session 2 (Conflicting Writer) | Modify same row and commit first |
| `demo2/demo2d-fk-slock.sql` | Single session | FK validation still takes S locks even under RCSI |
| `demo2/demo2e-fk-scan-conflict-session1.sql` | Session 1 (Snapshot) | DELETE order → error 3960 from FK range scan |
| `demo2/demo2e-fk-scan-conflict-session2.sql` | Session 2 (Writer) | UPDATE unrelated OrderItem triggers FK scan conflict |

### Part 3 — Internals & Costs

| Script | Sessions | Purpose |
|--------|----------|---------|
| `demo3/demo3a-version-chain-session1.sql` | Session 1 (Reader) | RCSI single-version read, Snapshot chain-walk proof via DBCC PAGE |
| `demo3/demo3a-version-chain-session2.sql` | Session 2 (Writer) | Single UPDATE (Beat 1), three UPDATEs building 3-hop chain (Beat 2) |
| `demo3/demo3b-instance-wide-impact-session1.sql` | Session 1 (Culprit) | Forgotten snapshot in eaglesdontfly; fix = COMMIT; verify cleanup |
| `demo3/demo3b-instance-wide-impact-session2.sql` | Session 2 (Victim OLTP) | 10 UPDATE waves on howboutthemcowboys; tempdb growth + chain depth proof |
| `demo3/demo3c-ghost-records.sql` | Single session | DELETE creates BOTH ghost record AND version record — two independent cleanup processes |

**Requires**: Start `demo3/dbcc_page_viewer.py` before demo3a.

### Part 4 — ADR & PVS

| Script | Sessions | Purpose |
|--------|----------|---------|
| `demo4/demo4a-adr-versioning-session1.sql` | Session 1 (Reader) | Beat 0: ADR ON/RCSI OFF — versions exist but reader blocks. Beat 1: enable RCSI+SNAPSHOT — in-row version (33-byte diff), PVS DMV queries, version chain walk, background cleaner observation |
| `demo4/demo4a-adr-versioning-session2.sql` | Session 2 (Writer) | Beat 0: UPDATE+ROLLBACK. Beat 1: three UPDATEs (Balance 200→300→400) with PVS DMV queries after each showing 0→1→2 off-row records |
| `demo4/demo4b-adr-offrow-versioning-session1.sql` | Session 1 (Reader) | Direct off-row: wide column (SavingsAccounts, CHAR(600) ComplianceNotes). Self-contained — does not require demo4a. PVS size immediately non-zero |
| `demo4/demo4b-adr-offrow-versioning-session2.sql` | Session 2 (Writer) | Single wide UPDATE on SavingsAccounts with PVS DMV query showing off-row record |
| `demo4/demo4c-pvs-cleaner-deep-dive.sql` | Session 1 | PVS Cleaner deep dive: async background timer, page-level cleanup, instance-wide XTS watermark |
| `demo4/demo4c-session2.sql` | Session 2 | Beat 2 companion — generates versions in eaglesdontfly, proves snapshot in another DB blocks cleanup via global XTS |
| `demo4/demo4d-pvs-watermark-pinning.sql` | Single session | Snapshot holds cleaner watermark, cross-table pinning proof, skip reasons, idle connection diagnostics, release and drain |
| `demo4/demo4e-adr-recovery.sql` | Single session | Large transaction rollback: traditional vs ADR near-instant rollback + PVS Cleaner live |

**Requires**: Start `demo4/dbcc_page_viewer_adr.py` before demo4a/4b.

#### ADR + RCSI: How the Engine Decides

Source code confirms ADR and RCSI are **completely independent flags** in the engine:

- `ADR ON, RCSI OFF` → `IsReadCommittedSnapshot()` returns `FALSE` → `SetStmtSnapshot()` never called → S locks on reads → **standard blocking**
- `ADR ON, RCSI ON` → `IsReadCommittedSnapshot()` returns `TRUE` → `SetStmtSnapshot()` called → version-based reads → **no reader/writer blocking**

ADR provides the persistent version store infrastructure (PVS), but it is the RCSI database option (`m_readCommittedSnapshot` on `DBTABLE`) that flips scan behavior from locking to versioning. ADR always generates PVS versions for every modification (for instant rollback and crash recovery) — those versions exist whether readers use them or not.

#### In-Row vs Off-Row Versioning Decision

ADR chooses between two version storage strategies:

- **In-row (SlotId = -4 / InRowDiff)**: The before-image diff is stored directly on the same data page as the current row. Requires sufficient free space on the page. No separate PVS page I/O.
- **Off-row (SlotId ≥ 0)**: The full before-image is written to a dedicated PVS page in the user database. Used when the data page lacks room for the in-row diff.

The deciding factor is the **size of the diff payload**, not just page free space. Demo4a (in-row) and demo4b (off-row) prove this: a narrow `Balance`-only update produces a ~33-byte diff that fits in-row. But when `ComplianceNotes CHAR(600)` is also updated on `SavingsAccounts` (demo4b), the ~600-byte diff can't fit in-row — ADR writes the before-image to a separate PVS page (off-row).

### Part 5 — Optimized Locking

| Script | Sessions | Purpose |
|--------|----------|---------|
| `demo5/demo5-optimized-locking.sql` | Single session | Lock count drops from thousands to 1 via TID locking + LAQ |

**Requires**: SQL Server 2025, ADR enabled.

### Part 6 — Benchmark

| Script | Sessions | Purpose |
|--------|----------|---------|
| `benchmark/demo6-benchmark.sql` | Single session | Creates `dbo.usp_BenchmarkWorkload` proc + config setup/reset |
| `benchmark/demo6-run-benchmark.ps1` | PowerShell | Orchestrates sqlsim to run workload under 4 configs (Baseline → RCSI → ADR+RCSI → ADR+RCSI+OL) |

## Utilities

| Script | Purpose |
|--------|---------|
| `tools/check-readiness.ps1` | Pre-session validation: files, SQL connectivity, features, permissions |
| `demo3/dbcc_page_viewer.py` | Flask web app — formatted DBCC PAGE output with tempdb version store chain (http://localhost:5050) |
| `demo4/dbcc_page_viewer_adr.py` | Flask web app — formatted DBCC PAGE output with ADR in-row/off-row PVS versioning (http://localhost:5051) |
| `tools/pvs-cleanup-blocker.sql` | PVS cleanup diagnostic — finds active snapshots, open transactions, and idle sessions pinning PVS versions |
| `tools/xevent-version-store-stats.sql` | XEvent session for `tx_version_additional_stats` — tempdb version store generation stats |
| `tools/_test_dbcc.sql` | Ad-hoc DBCC PAGE test (scratch file) |
| `tools/_test_slot41.py` | Ad-hoc hex dump parser for DBCC PAGE slot analysis (scratch file) |

## Multi-Session Scripts — SSMS Setup

For scripts with `-session1` / `-session2` suffixes:
1. Open Session 1 file in an SSMS query window connected to your SQL instance
2. Open Session 2 file in a **separate** SSMS query window (same instance)
3. Execute blocks step-by-step, following the `>>> Go to Session N` cues

## Dependencies

Each demo enables its own database settings (RCSI, Snapshot, ADR, OL) at the start — no demo depends on a previous demo's state. All are safe to run independently after `demo0/demo0-setup.sql`.

| Dependency | Used By |
|------------|---------|
| SQL Server 2025 | All demos (demo5 requires OL support) |
| sqlsim.exe | benchmark/demo6-run-benchmark.ps1 |
| Python + Flask + mssql_python | demo3/dbcc_page_viewer.py, demo4/dbcc_page_viewer_adr.py |

### Page Viewer — PVS Pinning Fix

Both page viewers use `mssql_python` connections with `autocommit = True`. This is critical: under RCSI, a connection without autocommit holds an implicit transaction after every query, which pins PVS versions indefinitely and prevents the background cleaner from reclaiming space. If you see PVS size staying non-zero with no active snapshot transactions, check for idle connections with `open_transaction_count > 0` (use `tools/pvs-cleanup-blocker.sql`).

## DBCC PAGE Viewer — Technical Details

Both page viewer apps (`demo3/dbcc_page_viewer.py` on port 5050, `demo4/dbcc_page_viewer_adr.py` on port 5051) decode internal SQL Server record structures from `DBCC PAGE ... WITH TABLERESULTS` output. These tools are for educational demo purposes only.

> **UNSUPPORTED / UNDOCUMENTED**: `DBCC PAGE` itself is an undocumented, unsupported command. While SQL Server has shipped it for decades and the output is widely known in the community, Microsoft does not document or guarantee its behavior.

### How it works

1. **Row lookup**: Uses `sys.dm_db_database_page_allocations()` to find data pages for `dbo.Accounts`, then scans each page via `DBCC PAGE(db, file, page, 3) WITH TABLERESULTS` to locate the target AccountId. This avoids taking locks on the user table during the demo.

2. **DBCC PAGE formatted output**: Format 3 produces a structured breakdown of each slot, including named fields for column values and — when a version pointer is present — version-related fields such as the version pointer address and transaction timestamp. The apps capture any field whose name contains "version", "xsn", or "timestamp" directly from this formatted output.

3. **Hex dump fallback**: DBCC PAGE format 3 also includes the raw hex dump of each record. If no named version fields are found in the formatted output, the apps fall back to parsing the hex dump directly: checking the record status byte (byte 0, bit 6 = `0x40`) for a version pointer and decoding the last 14 bytes of the record as the `RecVersioningInfo` structure. This fallback provides the granular field breakdown (PageId, FileId, SlotId, XdesTs, PVS flag) shown in the UI.

### 14-Byte Version Tag Layout (RecVersioningInfo)

> **UNSUPPORTED / UNDOCUMENTED**: The field-level binary layout below is derived from SQL Server source code internals. DBCC PAGE format 3 surfaces version pointer information in its formatted output, but the byte-level structure of the 14-byte tag — including the PVS flag in bit 31 and the SlotId special values — comes from source code knowledge and is not documented by Microsoft.

```
Offset  Size    Field               Notes
------  ------  ------------------  ----------------------------------------
0-3     4 bytes PageId (m_id)       Bit 31 = PVS flag (1 = PVS, 0 = tempdb)
                                    Bits 0-30 = page number
4-5     2 bytes FileId (m_file)     Database file ID
6-7     2 bytes SlotId (rid_slot)   Slot on the target page
                                    Special values:
                                      -4 (0xFFFC) = InRowDiff (ADR in-row version stub)
                                      >=0 = off-row version record slot
8-11    4 bytes XdesTs m_low        Transaction timestamp (low 32 bits)
12-13   2 bytes XdesTs m_high       Transaction timestamp (high 16 bits)
                                    Full XdesTs = (m_high << 32) | m_low
                                    Links to dm_tran_version_store.transaction_sequence_num
```

**Bytes 0-7** form the version chain pointer — where to find the before-image:
- **tempdb viewer** (`dbcc_page_viewer.py`): When bit 31 = 0, the pointer leads to a tempdb version store page. The app queries `sys.dm_tran_version_store` to display the full version chain with decoded row values.
- **ADR viewer** (`dbcc_page_viewer_adr.py`): When bit 31 = 1 (PVS flag), the pointer leads to a PVS page in the user database. The app queries `sys.dm_tran_persistent_version_store_stats` for PVS size and cleaner state.

**Bytes 6-7** (SlotId) distinguish ADR versioning strategies:
- **SlotId = -4 (InRowDiff)**: The before-image is stored as a diff stub directly on the same data page. Used for narrow column changes. No separate PVS page I/O needed.
- **SlotId >= 0**: The before-image is stored on a separate PVS page in the user database. Used for wider changes where the diff won't fit in-row.

### Version Store Record Decoding (tempdb viewer only)

The tempdb viewer also decodes `record_image_first_part` from `sys.dm_tran_version_store`. This binary blob is the raw row record in the same physical format as a data page record. Unlike the DBCC PAGE version fields above (which SQL Server formats for you), this is truly raw binary that the app must parse byte-by-byte.

> **UNSUPPORTED / UNDOCUMENTED**: The column offsets below are specific to the `dbo.Accounts` table schema created by `demo0-setup.sql`. The physical record layout depends on column order, data types, and fixed-length sizes. This is not a generic record parser.

```
Offset    Size     Column
------    ------   -----------------
0         1 byte   StatusA (record status)
1         1 byte   StatusB
2-3       2 bytes  Fixed-length data end offset (= 125)
4-7       4 bytes  AccountId (int)
8-16      9 bytes  Balance (decimal(18,2): byte 0 = sign, bytes 1-8 = value LE)
17-24     8 bytes  LastUpdated (datetime2(7))
25-124    100 bytes Filler (char(100))
125-126   2 bytes  Null bitmap column count
127       1 byte   Null bitmap bits
128-129   2 bytes  Variable column count
130+      variable Variable-length column end offsets, then AccountName (nvarchar), Status (nvarchar)
```

### StatusA Bit Flags (byte 0)

> **UNSUPPORTED / UNDOCUMENTED**: Internal record status flags.

| Bit | Mask | Meaning |
|-----|------|---------|
| 5 | 0x20 | Has variable-length columns |
| 6 | 0x40 | Has version pointer (14-byte tag appended) |

### In-Row Diff Payload Decoding (ADR viewer — ModifyRowVector format)

> **UNSUPPORTED / UNDOCUMENTED**: The in-row diff payload format is derived from SQL Server source code analysis. This is the internal `ModifyRowVector` serialization used by ADR's in-row versioning (SlotId = -4).

When ADR stores a version in-row, the diff payload is appended immediately after the 14-byte `RecVersioningInfo` tag. The payload uses a `ModifyRowVector` serialization format that encodes which record bytes changed and what their **old (pre-modification)** values were.

#### Payload location in the record

```
[record data] [14-byte version tag] [2-byte PayloadType+PayloadLen] [diff payload bytes]
                                     ^                               ^
                                     vp_offset + 14                  vp_offset + 16
```

- **PayloadType** (1 byte): `0x02` = `INROW_MODIFY_DIFF` (the only type we decode)
- **PayloadLen** (1 byte): Length of the diff payload that follows

#### ModifyRowVector serialized layout

```
Offset      Size            Field
------      ------          ------------------
0-3         4 bytes         Count (UINT32) — number of diff regions
4..         8 × Count       Sizes — interleaved pairs of UINT32:
                              [old_size₀, new_size₀, old_size₁, new_size₁, ...]
                              old_size = byte count in old record
                              new_size = byte count in new record
                              (equal for fixed-column changes)
+0          4 × Count       Offsets — interleaved pairs of UINT16:
                              [old_offset₀, new_offset₀, old_offset₁, new_offset₁, ...]
                              Record-relative byte offset of the changed region
+0          4 × Count       Padding — serialization overread artifact (skipped)
+0          Σ new_size[i]   Old values — the actual pre-modification bytes
```

**Key insight**: The payload stores **old** (pre-modification) values, not new ones. The current on-page row already has the new values. This is because the engine's `FindDiff` function is called with reversed arguments: `newRec.FindDiff(oldRec, ...)`, so `eNew` in the diff = the old record's bytes.

#### How the page viewer reconstructs the before-image

1. **Copy** the current on-page record bytes (which contain new/current values)
2. **Overlay** the old values from the diff payload at `new_offset` for each diff region
3. **Decode columns** from the reconstructed old row using the `dbo.Accounts` schema:
   - Balance `DECIMAL(18,2)` at record offset 8 (9 bytes: sign byte + 8-byte LE integer ÷ 100)
   - LastUpdated `DATETIME2(7)` at record offset 17 (8 bytes: 5-byte time + 3-byte date)

#### Worked example

For a `UPDATE SET Balance = 200.00, LastUpdated = SYSUTCDATETIME()` on AccountId 42:

```
Diff payload (33 bytes):
  01 00 00 00              Count = 1
  0D 00 00 00 0D 00 00 00  old_size = 13, new_size = 13
  09 00 09 00              old_offset = 9, new_offset = 9
  00 00 00 00              padding (4 bytes, skipped)
  45 06 01 00 00 00 00 00  old values: 13 bytes starting at record offset 9
  F4 68 85 95 88           (crosses Balance bytes 1-8 + LastUpdated bytes 0-4)
```

The viewer copies current row bytes, patches in the 13 old-value bytes at offset 9, then decodes Balance and LastUpdated from the patched row — showing the pre-UPDATE values in a green "BEFORE-IMAGE" box.
