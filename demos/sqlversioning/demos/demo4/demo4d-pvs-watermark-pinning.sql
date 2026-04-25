-- ============================================================================
-- DEMO 4d — PVS Watermark Pinning (Part 4: Accelerated Database Recovery)
--
-- What happens when the PVS Cleaner CAN'T clean. Snapshot transactions
-- hold the cleanup watermark — and the watermark is database-global,
-- not table-scoped. Proves cross-table version pinning.
--
-- Single session — no session 2 needed.
--
-- Prerequisites:
--   1. demo0-setup.sql has been run
--   2. ADR enabled on texasrangerswillwinitthisyear (demo4c setup does this)
-- ============================================================================
USE master;
GO

-- ============================================================================
-- SETUP: Ensure ADR + RCSI + SNAPSHOT are on
-- ============================================================================
ALTER DATABASE texasrangerswillwinitthisyear SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET ACCELERATED_DATABASE_RECOVERY = ON;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET READ_COMMITTED_SNAPSHOT ON;
ALTER DATABASE texasrangerswillwinitthisyear SET ALLOW_SNAPSHOT_ISOLATION ON;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET MULTI_USER;
GO

USE texasrangerswillwinitthisyear;
GO

-- Verify PVS is clean before starting
SELECT 
    persistent_version_store_size_kb AS PVS_Size_KB,
    current_aborted_transaction_count AS AbortedTxnCount
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID();
GO

-- ============================================================================
-- STEP 1: Pin the cleaner — snapshot holds the watermark
-- ============================================================================

-- TALKING POINT: "Now let me show you what happens when the cleaner
-- CAN'T clean. I'll open a snapshot transaction, generate versions,
-- and show the cleaner running but unable to reclaim anything."

-- Open a snapshot — this pins the cleanup watermark
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRAN;
    SELECT TOP 1 Id FROM dbo.BigTable;
    -- Snapshot is now established — our XSN becomes the cleanup floor
GO

-- Record PVS baseline with snapshot held
SELECT 
    persistent_version_store_size_kb AS PVS_Before_KB,
    offrow_version_cleaner_start_time AS CleanerStart
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID();
GO

-- Generate new versions while snapshot is held
-- These versions CANNOT be cleaned — our snapshot might need them
UPDATE dbo.BigTable SET Val = Val + 1, Payload = 'Watermark test batch A. Snapshot holds cleanup floor. Before-image preserved in PVS until watermark advances. Row eligible for cleanup only after snapshot commits. Original source: OLTP-Primary. ETL validated. Schema version 4.2. Data quality score: 97.3 percent. Upstream system confirmed. Downstream consumers: Risk, Compliance, Reporting. Retention: 7 years per regulatory mandate. Compression eligible after version cleanup. Audit trail appended with watermark test timestamp.' WHERE Id <= 50000;
GO
UPDATE dbo.BigTable SET Val = Val + 1, Payload = 'Watermark test batch B. Second update wave while snapshot active. Database-global watermark behavior. Cleanup blocked across all rows regardless of read set. Version chain depth increasing. PVS page allocation growing. Before-images accumulating in persistent version store allocation units. Cleaner will skip these pages until watermark advances past this commit timestamp. Pipeline reprocessing deferred until cleanup completes. Audit entry appended.' WHERE Id BETWEEN 50001 AND 100000;
GO

-- Now update a COMPLETELY UNRELATED table — Accounts
-- Our snapshot only read BigTable. We never touched Accounts.
-- But the watermark is database-global, not table-scoped.
UPDATE dbo.Accounts SET Balance = Balance + 0.01, Filler = 'Cross-table watermark test. Account not read by active snapshot but version is still pinned.';
GO

-- PVS grew — versions from BOTH tables are stuck
SELECT 
    persistent_version_store_size_kb AS PVS_After_Updates_KB
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID();
GO

-- Show PVS records broken down by table — proves cross-table pinning
SELECT 
    COALESCE(OBJECT_NAME(p.object_id), '(system)') AS TableName,
    COUNT(*) AS PVS_Records
FROM sys.dm_tran_persistent_version_store pvs
LEFT JOIN sys.partitions p ON pvs.rowset_id = p.hobt_id
GROUP BY p.object_id
ORDER BY PVS_Records DESC;
GO

-- TALKING POINT: "Look at that. PVS has versions from BigTable AND
-- Accounts. Our snapshot never read Accounts — we only did
-- SELECT TOP 1 FROM BigTable. But the watermark doesn't care.
-- It's a single timestamp, database-wide. Any version with a
-- commit_ts newer than our snapshot's start is pinned — regardless
-- of which table it belongs to."

-- Who's blocking cleanup?
SELECT 
    ast.session_id,
    ast.elapsed_time_seconds,
    ast.transaction_sequence_num AS SnapshotXSN,
    es.program_name,
    es.login_name
FROM sys.dm_tran_active_snapshot_database_transactions ast
JOIN sys.dm_exec_sessions es ON ast.session_id = es.session_id;
GO

-- Also check for idle connections holding implicit transactions
-- (Common with ORMs, connection pools, and tools without autocommit)
SELECT 
    es.session_id,
    es.program_name,
    es.login_name,
    es.open_transaction_count,
    es.last_request_end_time,
    DATEDIFF(SECOND, es.last_request_end_time, GETDATE()) AS idle_seconds
FROM sys.dm_exec_sessions es
WHERE es.open_transaction_count > 0
  AND es.is_user_process = 1
ORDER BY es.last_request_end_time;
GO

-- Force cleanup — it will try but can't reclaim pinned versions
EXEC sys.sp_persistent_version_cleanup @dbname = N'texasrangerswillwinitthisyear';
GO

-- Check skip reasons — why did the cleaner skip pages?
SELECT 
    pvs_off_row_page_skipped_low_water_mark     AS Skipped_LowWatermark,
    pvs_off_row_page_skipped_oldest_active_xdesid AS Skipped_OldestActiveXdes,
    pvs_off_row_page_skipped_min_useful_xts      AS Skipped_MinUsefulXts,
    pvs_off_row_page_skipped_oldest_snapshot      AS Skipped_OldestSnapshot
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID();
GO

-- PVS size should be unchanged — cleaner ran but couldn't reclaim
SELECT 
    persistent_version_store_size_kb AS PVS_Still_Pinned_KB,
    offrow_version_cleaner_start_time AS CleanerStart,
    offrow_version_cleaner_end_time AS CleanerEnd
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID();
GO

-- TALKING POINT: "The cleaner RAN — look at the timestamps. But PVS size
-- didn't drop. The skip counters tell you exactly why: oldest_snapshot.
-- Both BigTable AND Accounts versions are stuck. The cleaner is doing
-- its job — it's just not allowed to clean anything because our snapshot
-- is holding the watermark.
--
-- This is the same behavior as tempdb version store, but scoped to ONE
-- database. With tempdb, a forgotten snapshot in database A pins versions
-- for databases B, C, D — everyone shares the same tempdb. With PVS,
-- your mess stays in YOUR database. Other databases are unaffected.
-- That's the ADR win for cleanup isolation."

-- ============================================================================
-- STEP 2: Release the watermark — watch it drain
-- ============================================================================

-- TALKING POINT: "Now I'll commit the snapshot. The watermark advances.
-- The cleaner can finally reclaim."

COMMIT;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

-- No more active snapshots
SELECT COUNT(*) AS ActiveSnapshots
FROM sys.dm_tran_active_snapshot_database_transactions;
GO

-- Force cleanup now that watermark is released
EXEC sys.sp_persistent_version_cleanup @dbname = N'texasrangerswillwinitthisyear';
GO

WAITFOR DELAY '00:00:03';

-- PVS should be draining
SELECT 
    persistent_version_store_size_kb AS PVS_After_Release_KB,
    offrow_version_cleaner_start_time AS CleanerStart,
    offrow_version_cleaner_end_time AS CleanerEnd
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID();
GO

SELECT COUNT(*) AS PVS_Records_Remaining
FROM sys.dm_tran_persistent_version_store;
GO

-- TALKING POINT: "PVS drained. The cleaner reclaimed the space as soon
-- as the watermark advanced past those versions. In production, you
-- don't need to force this — the background timer handles it. But if
-- you see PVS growing, check dm_tran_active_snapshot_database_transactions.
-- That's your first diagnostic."

-- Reset Accounts so repeated runs don't drift
UPDATE dbo.Accounts SET Balance = Balance - 0.01, Filler = 'Standard retail checking. Branch referral. No overdraft protection. Monthly statement cycle.';
GO
