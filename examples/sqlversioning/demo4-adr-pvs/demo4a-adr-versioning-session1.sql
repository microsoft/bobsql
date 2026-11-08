-- ============================================================================
-- DEMO 4a — SESSION 1 (left window): ADR Versioning — The Reader
-- ADR behaves like RCSI: readers don't block writers, writers don't block
-- readers. But versions go to PVS in the user database, not tempdb.
-- Shows in-row versioning, promotion to off-row PVS, and version chains.
--
-- Load this in SSMS Session 1 (left window).
-- Load demo4a-adr-versioning-session2.sql in Session 2 (right window).
--
-- Prerequisites:
--   1. demo0-setup.sql has been run
--   2. ADR page viewer running: python demos/dbcc_page_viewer_adr.py
--   3. Browser open to http://localhost:5051
-- ============================================================================
USE texasrangerswillwinitthisyear;
GO

-- ============================================================================
-- SETUP: Enable ADR first (RCSI OFF), then turn RCSI ON separately
-- This two-step approach highlights a key architectural point:
-- ADR always generates PVS versions for recovery (rollback/crash).
-- RCSI controls whether READERS can use those versions.
-- ============================================================================
ALTER DATABASE texasrangerswillwinitthisyear SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO
-- Start with ADR ON but RCSI OFF — versions are generated but readers still lock
ALTER DATABASE texasrangerswillwinitthisyear SET ACCELERATED_DATABASE_RECOVERY = ON;
ALTER DATABASE texasrangerswillwinitthisyear SET READ_COMMITTED_SNAPSHOT OFF;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET MULTI_USER;
GO

-- Confirm state: ADR ON, RCSI OFF
SELECT name, 
    is_read_committed_snapshot_on AS RCSI,
    is_accelerated_database_recovery_on AS ADR
FROM sys.databases WHERE name = N'texasrangerswillwinitthisyear';
GO

-- Baseline: PVS should be clean, tempdb version store should be empty
SELECT 
    DB_NAME(database_id) AS [Database],
    reserved_space_kb AS TempDB_VersionStoreKB
FROM sys.dm_tran_version_store_space_usage
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');

SELECT 
    persistent_version_store_size_kb AS PVS_Size_KB,
    online_index_version_store_size_kb AS OnlineIdx_PVS_KB
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- TALKING POINT: "ADR is ON but RCSI is OFF. Here's the key insight:
-- ADR ALWAYS generates versions in PVS for every modification — that's
-- how it achieves instant rollback and crash recovery. Those versions
-- exist whether readers use them or not."

-- ============================================================================
-- BEAT 0: ADR ON, RCSI OFF — versions exist but readers still block
-- ============================================================================

-- >>> Go to Session 2: UPDATE AccountId 42 (don't commit).

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  >>> BROWSER: Enter 42 in "Find Row (AccountId)", click View Page.     ║
-- ║  >>> Audience sees: version tag on the row — ADR generated it.         ║
-- ║  >>> But the reader below will BLOCK, not use it.                      ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- This reader BLOCKS — even though ADR has a version available:
-- (Run this, observe the wait. Leave it blocking.)
SELECT AccountId, Balance FROM dbo.Accounts WHERE AccountId = 42;
GO

-- TALKING POINT: "Look at the page viewer — ADR created a version in PVS.
-- But our reader is BLOCKED. Under plain READ COMMITTED, the reader takes
-- an S lock and waits. The version is right there, but nobody told the
-- reader to use it. That's what RCSI does."

-- >>> Go to Session 2: ROLLBACK the update.

-- ============================================================================
-- Now enable RCSI + SNAPSHOT — readers can use the PVS versions
-- ============================================================================
ALTER DATABASE texasrangerswillwinitthisyear SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET READ_COMMITTED_SNAPSHOT ON;
ALTER DATABASE texasrangerswillwinitthisyear SET ALLOW_SNAPSHOT_ISOLATION ON;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET MULTI_USER;
GO

SELECT name, 
    is_read_committed_snapshot_on AS RCSI,
    is_accelerated_database_recovery_on AS ADR,
    snapshot_isolation_state_desc AS SnapshotIso
FROM sys.databases WHERE name = N'texasrangerswillwinitthisyear';
GO

-- TALKING POINT: "Now RCSI and SNAPSHOT isolation are both ON. ADR was
-- already generating versions for recovery. These SAME PVS versions also
-- serve readers — no tempdb needed. Two features, one version store.
-- We'll use SNAPSHOT isolation (transaction-level) to demonstrate
-- VERSION CHAINS — multiple versions of the same row linked together."

-- ============================================================================
-- BEAT 1: SNAPSHOT — In-Row to Off-Row Promotion + Version Chain
-- ============================================================================

-- TALKING POINT: "RCSI gives statement-level snapshots — each SELECT sees
-- the latest committed data at that instant. SNAPSHOT isolation freezes
-- the view for the ENTIRE TRANSACTION. We'll use it to show how ADR
-- stores versions and what happens when a second update hits."

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  >>> BROWSER: Enter 42 in "Find Row (AccountId)", click View Page.     ║
-- ║  >>> Clean slate — note the Balance value and row structure.            ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Start a SNAPSHOT transaction — our view is frozen at this point:
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
GO
BEGIN TRAN;
SELECT AccountId, AccountName, Balance, LastUpdated FROM dbo.Accounts WHERE AccountId = 42;
-- ^^^ Original committed values. Our snapshot is anchored here.
-- No matter how many updates happen, this transaction sees these values.
GO

-- >>> Go to Session 2: UPDATE #1 (Balance = 200) auto-commits.

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  >>> BROWSER: Click View Page (refresh).                               ║
-- ║  >>> Audience sees: IN-ROW version stub (slot = -4).                   ║
-- ║  >>>   The 33-byte diff payload is stored directly on the data page.  ║
-- ║  >>>   No separate PVS page needed — fast, compact.                   ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- TALKING POINT: "One update, one in-row version. ADR stored the before-image
-- as a diff payload right on the data page — just 33 bytes appended to the
-- row. No PVS page, no extra I/O. The page viewer shows slot = -4, which is
-- the engine's marker for an in-row diff. But what happens with a second
-- update from a different transaction?"

-- >>> Go to Session 2: UPDATE #2 (Balance = 300) auto-commits.

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  >>> BROWSER: Click View Page (refresh).                               ║
-- ║  >>> IN-ROW is GONE — now it's OFF-ROW (slot >= 0, PVS pointer).      ║
-- ║  >>> The page viewer chases the PVS pointer and shows the chain:       ║
-- ║  >>>   Current row: Balance = 300                                     ║
-- ║  >>>   PVS record V2 (stores 200) → PVS record V1 (stores original)  ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- TALKING POINT: "The in-row diff is a one-shot optimization. It can hold
-- exactly one version — there's no prev_row_in_chain pointer in the
-- in-row format. When a second transaction modifies the same row, the
-- engine evicts the in-row diff to a PVS page and creates a second PVS
-- record for the new before-image. Now they're chained via
-- prev_row_in_chain — a proper off-row version chain."

-- Read under SNAPSHOT — engine walks the PVS version chain:
SELECT AccountId, Balance FROM dbo.Accounts WHERE AccountId = 42;
-- ^^^ Gets the ORIGINAL Balance, not 300, not 200.
-- The engine walked the PVS chain to find the value at our snapshot.
GO

-- WHERE are the versions? Now PVS is non-zero:
SELECT 
    persistent_version_store_size_kb AS PVS_Size_KB
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
-- ^^^ Non-zero — the evicted versions are off-row PVS records.
GO

-- TALKING POINT: "After the first update, PVS was empty — the version was
-- in-row on the data page. After the second update, PVS grew — both versions
-- were evicted off-row. The PVS DMV only sees off-row versions. In-row
-- versions are invisible to it — they live on the data page itself."

COMMIT;  -- End our SNAPSHOT transaction
GO

-- Outside SNAPSHOT — now sees the latest committed value:
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO
SELECT AccountId, Balance FROM dbo.Accounts WHERE AccountId = 42;
-- ^^^ Balance = 300. Both updates committed.
GO

-- TALKING POINT: "Both updates were committed, but our SNAPSHOT reader
-- still saw the original value — transaction-level consistency. Only after
-- we ended the snapshot did we see the new value."

-- PVS still has versions — but now no snapshot pins them:
SELECT 
    persistent_version_store_size_kb AS PVS_Size_KB,
    aborted_version_cleaner_start_time AS LastCleanerStart,
    aborted_version_cleaner_end_time AS LastCleanerEnd
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- TALKING POINT: "PVS is still non-zero — the versions are there. But
-- the background PVS cleaner runs roughly every minute. Since we just
-- ended the last snapshot, those versions are now reclaimable. Let's
-- wait a moment and check again..."

-- >>> Wait ~60 seconds, then re-run this query:
SELECT 
    persistent_version_store_size_kb AS PVS_Size_KB_After_Cleaner,
    aborted_version_cleaner_start_time AS LastCleanerStart,
    aborted_version_cleaner_end_time AS LastCleanerEnd
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- If PVS is still non-zero, something is pinning versions. Find out who:
SELECT 
    ast.session_id,
    ast.elapsed_time_seconds,
    at.transaction_begin_time,
    es.program_name
FROM sys.dm_tran_active_snapshot_database_transactions ast
JOIN sys.dm_tran_active_transactions at ON ast.transaction_id = at.transaction_id
JOIN sys.dm_exec_sessions es ON ast.session_id = es.session_id;
GO

-- TALKING POINT: "If PVS won't clean up, this query tells you exactly
-- who's pinning it — session ID, how long it's been open, and which 
-- application. Any active snapshot transaction prevents the cleaner 
-- from reclaiming versions created before that snapshot started."

-- TALKING POINT: "Zero. The background cleaner picked it up automatically.
-- No manual intervention needed — the engine manages PVS lifecycle on its
-- own. In production, you never have to call sp_persistent_version_cleanup
-- unless you're debugging. The cleaner just works."

-- >>> Continue to demo4b-adr-offrow-versioning: Direct off-row versioning with wide columns.