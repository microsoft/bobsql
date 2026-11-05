-- ============================================================================
-- DEMO 4d — ADR + PVS Cleaner (Part 4: Accelerated Database Recovery)
-- Duration: 3 min (50) | 5 min (60) | 8 min (75)
--
-- Large transaction rollback: traditional vs ADR. Then PVS Cleaner live.
-- ============================================================================
USE texasrangerswillwinitthisyear;
GO

-- ============================================================================
-- ENSURE REQUIRED STATE: RCSI ON, Snapshot ON, ADR OFF (we enable it in Step 2)
-- ============================================================================
ALTER DATABASE texasrangerswillwinitthisyear SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET OPTIMIZED_LOCKING = OFF;
ALTER DATABASE texasrangerswillwinitthisyear SET ACCELERATED_DATABASE_RECOVERY = OFF;
ALTER DATABASE texasrangerswillwinitthisyear SET READ_COMMITTED_SNAPSHOT ON;
ALTER DATABASE texasrangerswillwinitthisyear SET ALLOW_SNAPSHOT_ISOLATION ON;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET MULTI_USER;
GO

-- Verify version stores are clean before starting
-- If not zero, wait 15 seconds and re-run. If still not zero, re-run demo0-setup.sql.
SELECT 
    DB_NAME(database_id) AS [Database],
    reserved_space_kb AS TempDB_VersionStoreKB
FROM sys.dm_tran_version_store_space_usage
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');

SELECT 
    persistent_version_store_size_kb AS PVS_KB
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
-- Both should be 0 or near 0. PVS query may return no rows if ADR was never enabled — that's fine.
GO

-- ============================================================================
-- STEP 1: Traditional rollback — time the pain
-- ============================================================================

-- Confirm ADR is OFF
SELECT name, 
    is_read_committed_snapshot_on AS RCSI,
    is_accelerated_database_recovery_on AS ADR
FROM sys.databases WHERE name = N'texasrangerswillwinitthisyear';
GO

-- Start a large UPDATE, then cancel/rollback — time it
PRINT N'=== Traditional rollback (no ADR) ===';
PRINT N'Starting large UPDATE on 500K rows...';
DECLARE @start DATETIME2 = SYSUTCDATETIME();

BEGIN TRAN;
    UPDATE dbo.BigTable SET Val = Val + 1;
    -- Rows affected: ~500,000
    
    PRINT N'UPDATE complete. Now rolling back...';
    DECLARE @rollback_start DATETIME2 = SYSUTCDATETIME();
ROLLBACK;

DECLARE @rollback_end DATETIME2 = SYSUTCDATETIME();
PRINT N'Rollback time (traditional): ' 
    + CAST(DATEDIFF(MILLISECOND, @rollback_start, @rollback_end) AS NVARCHAR(20)) + N' ms';
GO

-- TALKING POINT: "That rollback had to undo every single row change
-- by reading log records backward and applying compensation records.
-- 500K rows = real time. Now imagine 50 million rows. Or a 2-hour 
-- transaction that gets killed. That's the problem ADR solves."

-- ============================================================================
-- STEP 2: Enable ADR
-- ============================================================================
ALTER DATABASE texasrangerswillwinitthisyear SET ACCELERATED_DATABASE_RECOVERY = ON;
GO

SELECT name, is_accelerated_database_recovery_on AS ADR
FROM sys.databases WHERE name = N'texasrangerswillwinitthisyear';
-- ADR = 1
GO

-- ============================================================================
-- STEP 3: ADR rollback — near-instant
-- ============================================================================
PRINT N'=== ADR rollback ===';
PRINT N'Starting large UPDATE on 500K rows (with ADR)...';

BEGIN TRAN;
    UPDATE dbo.BigTable SET Val = Val + 1;
    -- Rows affected: ~500,000
    
    PRINT N'UPDATE complete. Now rolling back (ADR)...';
    DECLARE @rollback_start2 DATETIME2 = SYSUTCDATETIME();
ROLLBACK;

DECLARE @rollback_end2 DATETIME2 = SYSUTCDATETIME();
PRINT N'Rollback time (ADR): ' 
    + CAST(DATEDIFF(MILLISECOND, @rollback_start2, @rollback_end2) AS NVARCHAR(20)) + N' ms';
GO

-- TALKING POINT: "Near-instant. ADR used logical revert — it read the
-- old versions from PVS instead of undoing each log record. The database
-- was available the entire time. Same result, fraction of the time."

-- ============================================================================
-- STEP 4: Show PVS stats — where did the versions go?
-- ============================================================================
SELECT 
    persistent_version_store_size_kb AS PVS_Size_KB,
    online_index_version_store_size_kb AS OnlineIdx_PVS_KB,
    current_aborted_transaction_count AS AbortedTxnCount,
    aborted_version_cleaner_start_time AS LastCleanerStart,
    aborted_version_cleaner_end_time AS LastCleanerEnd
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- TALKING POINT: "Versions are in PVS — in our user database. Not tempdb.
-- The PVS Cleaner will reclaim this space in the background."

-- Check: tempdb version store should be empty for this database
SELECT 
    DB_NAME(database_id) AS [Database],
    reserved_space_kb AS TempDB_VersionKB
FROM sys.dm_tran_version_store_space_usage
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- ============================================================================
-- [+60] STEP 5: PVS Cleaner live — watch it drain
-- ============================================================================
-- TALKING POINT: "Let me show you the PVS Cleaner in action.
-- I'll hold versions alive with a snapshot, generate some, then 
-- release and watch the cleaner do its thing."

-- Start a snapshot transaction to hold versions
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRAN;
    SELECT TOP 1 Id FROM dbo.BigTable;
    -- Snapshot established — versions must be kept
GO

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SESSION 2 — Generate versions while snapshot is held                   ║
-- ╚══════════════════════════════════════════════════════════════════════════╝
-- Run in Session 2:
USE texasrangerswillwinitthisyear;
UPDATE dbo.BigTable SET Val = Val + 1 WHERE Id <= 100000;
GO
UPDATE dbo.BigTable SET Val = Val + 1 WHERE Id BETWEEN 100001 AND 200000;
GO

-- Check PVS size (should be growing):
SELECT 
    persistent_version_store_size_kb AS PVS_Size_KB,
    current_aborted_transaction_count AS AbortedTxnCount
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- Who's blocking cleanup?
SELECT 
    session_id,
    transaction_id,
    elapsed_time_seconds
FROM sys.dm_tran_active_snapshot_database_transactions;
GO

-- TALKING POINT: "PVS is growing because our snapshot transaction is 
-- holding the cleanup watermark. The cleaner wakes up every ~60 seconds,
-- checks, and can't clean anything. Let's release it."

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SESSION 1 — Release the snapshot                                       ║
-- ╚══════════════════════════════════════════════════════════════════════════╝
COMMIT;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

-- Wait for the background cleaner (could take up to 60 seconds)
-- Or force it:
PRINT N'Forcing PVS cleanup...';
EXEC sys.sp_persistent_version_cleanup @dbname = N'texasrangerswillwinitthisyear';
GO

-- Check PVS after cleanup:
SELECT 
    persistent_version_store_size_kb AS PVS_Size_KB,
    current_aborted_transaction_count AS AbortedTxnCount,
    aborted_version_cleaner_start_time AS LastCleanerStart,
    aborted_version_cleaner_end_time AS LastCleanerEnd
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- TALKING POINT: "PVS drained. The cleaner reclaimed the space. In production
-- you shouldn't need to force this — the background cleaner runs automatically.
-- But if you see PVS growing, check dm_tran_active_snapshot_database_transactions
-- for long-running readers holding the watermark."

-- ============================================================================
-- [+60] STEP 5B: Ghost Records vs PVS under ADR
-- ============================================================================
-- TALKING POINT: "In Demo 3, we saw ghost records and version records with  
-- tempdb versioning. With ADR on, the versions move to PVS — but ghost 
-- records still work the same way. Let's prove it."

-- Step 1: Check ghost records and PVS before
SELECT 
    OBJECT_NAME(object_id) AS TableName,
    ghost_record_count,
    version_ghost_record_count
FROM sys.dm_db_index_physical_stats(
    DB_ID(N'texasrangerswillwinitthisyear'), 
    OBJECT_ID(N'dbo.BigTable'), 
    1, NULL, 'DETAILED')
WHERE index_level = 0;
GO

SELECT 
    persistent_version_store_size_kb AS PVS_Before_KB
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- Step 2: Start snapshot, DELETE rows
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRAN;
    SELECT TOP 1 Id FROM dbo.BigTable;
GO

-- Session 2: delete 1000 rows from BigTable
DELETE FROM dbo.BigTable WHERE Id BETWEEN 1 AND 1000;
GO

-- Step 3: Check — ghost records on page + versions in PVS (not tempdb!)
SELECT 
    OBJECT_NAME(object_id) AS TableName,
    ghost_record_count,
    version_ghost_record_count
FROM sys.dm_db_index_physical_stats(
    DB_ID(N'texasrangerswillwinitthisyear'), 
    OBJECT_ID(N'dbo.BigTable'), 
    1, NULL, 'DETAILED')
WHERE index_level = 0;
GO

SELECT 
    persistent_version_store_size_kb AS PVS_After_KB
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- Confirm tempdb version store is NOT being used:
SELECT 
    DB_NAME(database_id) AS [Database],
    reserved_space_kb AS TempDB_VersionKB
FROM sys.dm_tran_version_store_space_usage
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- TALKING POINT: "Ghost records: still on the data page — same as before.
-- But the version records? They're in PVS, not tempdb.
--
-- Here's a key difference from Demo 3c. With tempdb versioning, ghost
-- cleanup and version store cleanup are fully independent — two janitors
-- cleaning two different rooms, no coordination needed. With PVS, that
-- changes. Version ghost records — ghosts from DELETEs — can't be removed
-- from the data page until the PVS Cleaner has cleaned up the associated
-- version record first. The ghost points into PVS. Remove the ghost before
-- PVS cleanup, and you orphan the version record.
--
-- So under ADR there's a dependency chain:
--   1. PVS Cleaner runs (~60s timer) → removes version from PVS
--   2. Ghost Cleaner runs (~10s timer) → NOW it can remove the version ghost
--
-- If PVS cleanup stalls (pinned watermark), version ghosts pile up on
-- data pages → page bloat → scans slow down. The root cause looks like
-- ghost cleanup is broken, but the real problem is the PVS watermark.
--
-- The ADR win is still real — PVS is per-database, so one database
-- can't starve another. But within a database, PVS cleanup is the
-- gatekeeper for version ghost cleanup."

-- Step 4: Commit and force cleanup of both
COMMIT;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

EXEC sys.sp_persistent_version_cleanup @dbname = N'texasrangerswillwinitthisyear';
GO

-- Re-check after cleanup
SELECT 
    OBJECT_NAME(object_id) AS TableName,
    ghost_record_count
FROM sys.dm_db_index_physical_stats(
    DB_ID(N'texasrangerswillwinitthisyear'), 
    OBJECT_ID(N'dbo.BigTable'), 
    1, NULL, 'DETAILED')
WHERE index_level = 0;
GO

SELECT 
    persistent_version_store_size_kb AS PVS_After_Cleanup_KB
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- Re-seed deleted BigTable rows
INSERT INTO dbo.BigTable (Val)
SELECT TOP (1000) ABS(CHECKSUM(NEWID())) % 1000
FROM sys.all_objects a;
GO

-- ============================================================================
-- [+75] STEP 6: Kill process mid-transaction — time recovery
-- ============================================================================
-- WARNING: This step kills the SQL Server process. Only do this if you have
-- a dedicated demo instance. Skip on shared environments.

-- Uncomment to run:
/*
PRINT N'Starting a large transaction that we will kill mid-flight...';
BEGIN TRAN;
    UPDATE dbo.BigTable SET Val = Val + 1;
    -- Now kill the SQL Server process from Task Manager or:
    -- SHUTDOWN WITH NOWAIT;
    
-- After restart, time the recovery:
-- Check the SQL Server error log for:
--   "Recovery of database 'texasrangerswillwinitthisyear' (xx) is yy% complete"
--   "Recovery completed" 
-- With ADR the Undo phase should be near-instant regardless of transaction size
*/

-- Instead, show the recovery time from the error log of a previous demo:
EXEC sys.xp_readerrorlog 0, 1, N'texasrangerswillwinitthisyear', N'Recovery';
GO

-- ============================================================================
-- CLEANUP — Leave ADR ON (needed for D6 Optimized Locking)
-- ============================================================================
