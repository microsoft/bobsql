-- ============================================================================
-- DEMO 4b — SESSION 1 (left window): Direct Off-Row — Wide Column to PVS
-- In demo4a, the first version fit in-row because the diff was small
-- (33 bytes). But ADR has a 200-byte limit for in-row payloads.
-- When the diff exceeds that — like updating a 600-byte column — the engine
-- writes the version directly to a PVS page. No in-row step at all.
--
-- Load this in SSMS Session 1 (left window).
-- Load demo4b-adr-offrow-versioning-session2.sql in Session 2 (right window).
--
-- Prerequisites:
--   1. demo0-setup.sql has been run
--   2. ADR page viewer running: python demos/dbcc_page_viewer_adr.py
--   3. Browser open to http://localhost:5051
-- ============================================================================
USE texasrangerswillwinitthisyear;
GO

-- ============================================================================
-- SETUP: Ensure ADR + RCSI + SNAPSHOT are ON
-- ============================================================================
ALTER DATABASE texasrangerswillwinitthisyear SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET ACCELERATED_DATABASE_RECOVERY = ON;
ALTER DATABASE texasrangerswillwinitthisyear SET READ_COMMITTED_SNAPSHOT ON;
ALTER DATABASE texasrangerswillwinitthisyear SET ALLOW_SNAPSHOT_ISOLATION ON;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET MULTI_USER;
GO

-- ============================================================================
-- Direct Off-Row — Wide Column Goes Straight to PVS
-- ============================================================================

-- TALKING POINT: "In demo4a, the first version fit in-row because the diff
-- was small (33 bytes). But ADR has a 200-byte limit for in-row payloads.
-- When the diff exceeds that — like updating a 600-byte column — the engine
-- writes the version directly to a PVS page. No in-row step at all."

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  >>> BROWSER: Select "SavingsAccounts" from the Table dropdown.        ║
-- ║  >>> Enter 42 in "Find Row (AccountId)", click View Page.              ║
-- ║  >>> Note ComplianceNotes — a 600-byte CHAR column.                    ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Start a SNAPSHOT transaction:
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
GO
BEGIN TRAN;
SELECT AccountId, Balance, Status FROM dbo.SavingsAccounts WHERE AccountId = 42;
-- ^^^ Original values. Snapshot anchored.
GO

-- >>> Go to Session 2: UPDATE SavingsAccounts (wide column) auto-commits.
-- >>> Just ONE update — that's all we need.

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  >>> BROWSER: Click View Page (refresh).                               ║
-- ║  >>> OFF-ROW immediately: SlotId >= 0 (PVS pointer).                  ║
-- ║  >>> No in-row step — the 600-byte diff exceeded the 200-byte limit.  ║
-- ║  >>> Single PVS record, no chain (only one update).                    ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Reader uses the PVS version:
SELECT AccountId, Balance, Status FROM dbo.SavingsAccounts WHERE AccountId = 42;
-- ^^^ Gets the ORIGINAL values — read from the PVS record.
GO

-- PVS grew from the off-row version:
SELECT 
    persistent_version_store_size_kb AS PVS_Size_KB
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- TALKING POINT: "One update, one off-row PVS record. The diff payload was
-- ~600 bytes — way over the 200-byte in-row limit. The engine went straight
-- to PVS, no in-row optimization possible. The PVS DMV shows non-zero
-- because the version is off-row. Compare to demo4a where the first small
-- update was invisible to the DMV because it was in-row."

COMMIT;  -- End SNAPSHOT transaction
GO

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO
SELECT AccountId, Balance FROM dbo.SavingsAccounts WHERE AccountId = 42;
-- ^^^ Latest committed value.
GO

-- TALKING POINT: "Two reasons versions go off-row: (1) the diff is too
-- large for in-row — we just saw that. (2) A second transaction modifies
-- a row that already has an in-row version — demo4a showed that.
-- Either way, off-row versions live in PVS pages in the user database."

-- ============================================================================
-- WRAP-UP: PVS is in the user database — prove it
-- ============================================================================

-- Where is PVS space allocated?
SELECT 
    persistent_version_store_size_kb AS PVS_Size_KB,
    online_index_version_store_size_kb AS OnlineIdx_PVS_KB,
    current_aborted_transaction_count AS AbortedTxnCount,
    aborted_version_cleaner_start_time AS LastCleanerStart,
    aborted_version_cleaner_end_time AS LastCleanerEnd
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- tempdb remains clean — no versions there
SELECT 
    DB_NAME(database_id) AS [Database],
    reserved_space_kb AS TempDB_VersionStoreKB
FROM sys.dm_tran_version_store_space_usage
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- Force PVS cleanup
EXEC sys.sp_persistent_version_cleanup @dbname = N'texasrangerswillwinitthisyear';
GO

SELECT 
    persistent_version_store_size_kb AS PVS_Size_KB_After_Cleanup
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- TALKING POINT: "Versions are in the user database. PVS cleaner reclaims 
-- space in the background. And tempdb? Never touched. That's the key 
-- architectural shift with ADR: per-database versioning, no tempdb 
-- contention, and the same reader-doesn't-block-writer guarantee."
