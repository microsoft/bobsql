-- ============================================================================
-- demo4c-session2.sql — Instance-wide XTS watermark demo (Session 2)
-- ============================================================================
-- Run this in a SEPARATE query window from demo4c-pvs-cleaner-deep-dive.sql
-- 
-- Session 1 (demo4c): Opens snapshot in texasrangerswillwinitthisyear to pin
--                      the instance-wide XTS watermark
-- Session 2 (this script): Generates versions in eaglesdontfly, shows
--                           cleanup is BLOCKED by the other DB's snapshot,
--                           then shows cleanup succeeds after release
--
-- PREREQUISITE: Session 1 must have run through Step 2 (snapshot is open)
--               before you start this script.
-- ============================================================================

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- Step 1: Generate versions in eaglesdontfly (different database entirely)
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
USE eaglesdontfly;
UPDATE dbo.ReportData SET Score = Score + 1, Notes = 'Instance-wide XTS watermark test. Snapshot is open in texasrangerswillwinitthisyear — not this database. Cleanup should be BLOCKED because the XTS floor is instance-wide. Scouting report revision: Film review complete for weeks 1 through 12. Defensive coordinator recommends man coverage on third down. Offensive line grading shows improvement at right tackle. Practice squad callups pending for cornerback depth.';
GO

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- Step 2: Show PVS size in eaglesdontfly — versions are present
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
SELECT 
    DB_NAME(database_id) AS [Database],
    persistent_version_store_size_kb AS PVS_Size_KB
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID(N'eaglesdontfly');
GO

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- Step 3: Force cleanup on eaglesdontfly — should NOT clean
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
EXEC sys.sp_persistent_version_cleanup @dbname = N'eaglesdontfly';
GO

SELECT 
    DB_NAME(database_id) AS [Database],
    persistent_version_store_size_kb AS PVS_After_Cleanup_KB
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID(N'eaglesdontfly');
GO

-- TALKING POINT: "PVS size didn't change. Cleanup ran but couldn't
-- reclaim anything. Let's look at the skip counters to see why."

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- Step 4: Skip counters — min_useful_xts proves XTS is the blocker
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
SELECT 
    pvs_off_row_page_skipped_min_useful_xts AS Skipped_MinUsefulXts,
    pvs_off_row_page_skipped_oldest_snapshot AS Skipped_OldestSnapshot,
    pvs_off_row_page_skipped_low_water_mark AS Skipped_LowWatermark
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID(N'eaglesdontfly');
GO

-- TALKING POINT: "Skipped_MinUsefulXts is nonzero — that's the instance-wide
-- XTS floor set by our snapshot in texasrangerswillwinitthisyear. Notice
-- Skipped_OldestSnapshot is 0 — there's no snapshot in eaglesdontfly.
-- The cleaner is blocked by a DIFFERENT database's snapshot."

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- Step 5: Who's holding the XTS floor?
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
SELECT 
    ast.session_id,
    ast.elapsed_time_seconds,
    ast.transaction_sequence_num AS SnapshotXSN,
    ast.first_snapshot_sequence_num,
    es.program_name
FROM sys.dm_tran_active_snapshot_database_transactions ast
JOIN sys.dm_exec_sessions es ON ast.session_id = es.session_id;
GO

-- Show both databases have the same min_transaction_timestamp (global XTS)
SELECT 
    DB_NAME(database_id) AS [Database],
    min_transaction_timestamp AS XTS_Floor,
    persistent_version_store_size_kb AS PVS_Size_KB
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id IN (
    DB_ID(N'texasrangerswillwinitthisyear'),
    DB_ID(N'eaglesdontfly')
);
GO

-- TALKING POINT: "Same min_transaction_timestamp in both databases — that's
-- the global XTS floor. The docs confirm it: 'instance-level transaction
-- timestamps are used even in single-database transactions, because any
-- transaction might be promoted to a cross-database transaction.'
-- PVS gives you STORAGE isolation — your versions are in your own filegroup,
-- not competing for tempdb space. But the cleanup WATERMARK has a global
-- component through XTS. Now let me release the snapshot..."

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- >>> SWITCH TO SESSION 1 and run the COMMIT (Step 3) <<<
-- >>> Then come back here for the final cleanup <<<
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- Step 6: Force cleanup after snapshot released — eaglesdontfly drains
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
EXEC sys.sp_persistent_version_cleanup @dbname = N'eaglesdontfly';
GO

SELECT 
    DB_NAME(database_id) AS [Database],
    persistent_version_store_size_kb AS PVS_After_Release_KB
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID(N'eaglesdontfly');
GO

-- TALKING POINT: "Snapshot released, eaglesdontfly cleaned immediately.
-- Key takeaway: PVS gives you storage isolation — no tempdb bloat, no
-- GAM/SGAM contention, versions survive restart. But a long-running
-- snapshot anywhere on the instance pins cleanup everywhere.
-- Find the holder, fix the holder."

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- Restore eaglesdontfly to original state
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
USE master;
GO
ALTER DATABASE eaglesdontfly SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
ALTER DATABASE eaglesdontfly SET ACCELERATED_DATABASE_RECOVERY = OFF;
ALTER DATABASE eaglesdontfly SET MULTI_USER;
GO
