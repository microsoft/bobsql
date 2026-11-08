-- ============================================================================
-- DEMO 4c — PVS Cleaner Deep Dive
-- How the background cleaner works and the parallel cleaner thread pool
-- (SQL Server 2022+).
--
-- Single session — no session 2 needed.
-- Watermark pinning is covered separately in demo4d.
--
-- Prerequisites:
--   1. demo0-setup.sql has been run
--
-- This demo addresses Andy Yun's request for a deep dive into the PVS
-- Cleaner process, including how it works as an async background task
-- and how it relates to Index Compaction.
-- ============================================================================
USE master;
GO

-- ============================================================================
-- SETUP: ADR + RCSI + SNAPSHOT
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

-- ============================================================================
-- BEAT 0: Baseline — PVS is clean
-- ============================================================================

-- TALKING POINT: "Let's look at the PVS Cleaner. This is the background
-- process that reclaims version records. It's async — and that one word
-- is the key to understanding everything about PVS cleanup, including
-- why Index Compaction works the way it does."

-- Current PVS state — should be 0 or near 0
SELECT 
    persistent_version_store_size_kb AS PVS_Size_KB,
    current_aborted_transaction_count AS AbortedTxnCount,
    offrow_version_cleaner_start_time AS OffRow_CleanerStart,
    offrow_version_cleaner_end_time AS OffRow_CleanerEnd
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID();
GO

-- PVS records — should be 0
SELECT COUNT(*) AS PVS_Record_Count
FROM sys.dm_tran_persistent_version_store;
GO

-- If any PVS records exist, show which objects they belong to
-- (ADR versions everything — including system catalog tables)
SELECT 
    COALESCE(OBJECT_NAME(p.object_id), '(system)') AS TableName,
    COUNT(*) AS PVS_Records
FROM sys.dm_tran_persistent_version_store pvs
LEFT JOIN sys.partitions p ON pvs.rowset_id = p.hobt_id
GROUP BY p.object_id
ORDER BY PVS_Records DESC;
GO

-- TALKING POINT: "Clean slate. No versions in PVS. The cleaner has nothing
-- to do. Let's generate some work for it."

-- ============================================================================
-- BEAT 1: Generate PVS versions — watch them accumulate
-- ============================================================================

-- TALKING POINT: "I'll update 100K rows including a wide column.
-- The wide diff forces ADR to write the before-image off-row to PVS.
-- Watch the PVS size jump."

UPDATE dbo.BigTable SET Val = Val + 1, Payload = 'Reprocessed during PVS cleanup demo. Record superseded. Version history maintained in persistent version store. Audit trail preserved for compliance. Timestamp appended. Original source: OLTP-Primary batch ingest. Schema version 4.2. Data quality score recalculated after reprocessing. Upstream validation passed. Downstream consumers notified: Risk, Compliance, Reporting. Retention policy unchanged: 7 years per regulatory mandate. No exceptions flagged during reprocessing cycle.' WHERE Id <= 100000;
GO

-- PVS grew — versions are in the store
SELECT 
    persistent_version_store_size_kb AS PVS_Size_KB,
    offrow_version_cleaner_start_time AS OffRow_CleanerStart,
    offrow_version_cleaner_end_time AS OffRow_CleanerEnd
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID();
GO

-- How many PVS records?
SELECT COUNT(*) AS PVS_Record_Count
FROM sys.dm_tran_persistent_version_store;
GO

-- Which objects generated PVS versions?
SELECT 
    COALESCE(OBJECT_NAME(p.object_id), '(system)') AS TableName,
    COUNT(*) AS PVS_Records
FROM sys.dm_tran_persistent_version_store pvs
LEFT JOIN sys.partitions p ON pvs.rowset_id = p.hobt_id
GROUP BY p.object_id
ORDER BY PVS_Records DESC;
GO

-- TALKING POINT: "PVS now has ~100K version records. But here's the thing:
-- nobody needs these versions. No snapshot transaction is open. No reader
-- needs the before-images. So why are they still here?"

-- TALKING POINT: "Because the cleaner is ASYNC. It runs on a timer —
-- roughly every 60 seconds. It doesn't clean inline with your DML.
-- Your UPDATE finishes instantly. The cleanup happens later, in the
-- background, on a separate thread. This is by design — you don't
-- want cleanup overhead in your transaction's hot path."
--
-- Re-run the Beat 0 queries to watch the cleaner drain PVS.
-- Watch the cleaner timestamps change and the size drop.
--
-- TALKING POINT: "Nobody told it to run. No maintenance window. No job.
-- It just does its thing in the background, every ~60 seconds.
-- This is EXACTLY how Index Compaction works too. When the cleaner
-- visits a data page to reclaim in-row version space, it can also
-- compact the page layout. Same timer. Same background thread.
-- If the cleaner falls behind, compaction doesn't happen either."
--
-- NOTE: Watermark pinning (snapshot holds cleaner, cross-table proof,
-- release and drain) is covered in demo4d-pvs-watermark-pinning.sql.

-- After the cleaner drains PVS, a few residual records will remain on
-- partially-filled cached PVS pages. The cleaner only processes FULL
-- pages — partially-filled pages stay in the PVS cache indefinitely,
-- available for future version writes. Disabling ADR forces the engine
-- to mark all pre-allocated pages as full and evict the cache.
USE master;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET ACCELERATED_DATABASE_RECOVERY = OFF;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET MULTI_USER;
GO
USE texasrangerswillwinitthisyear;
GO

-- Confirm PVS is now truly empty
-- Need to wait for cleaner to finish and evict cached pages before this returns 0
SELECT COUNT(*) AS PVS_Record_Count
FROM sys.dm_tran_persistent_version_store;
GO

-- ============================================================================
-- BEAT 2: Instance-wide XTS watermark — snapshot in one DB blocks all DBs
--         *** This beat uses TWO sessions ***
--         Session 1 (this script): opens snapshot, then releases it
--         Session 2 (demo4c-session2.sql): generates versions in a
--         DIFFERENT database, shows cleanup is blocked, then unblocked
-- ============================================================================

-- TALKING POINT: "You might think PVS gives you per-database cleanup
-- isolation — my snapshot is in database A, so database B should clean
-- freely. But that's not how it works. The XTS timestamp is INSTANCE-WIDE.
-- The docs say: 'These instance-level transaction timestamps are used even
-- in single-database transactions, because any transaction might be promoted
-- to a cross-database transaction.' Let me prove it."

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- SESSION 1 — Step 1: Enable ADR on eaglesdontfly
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
USE master;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET ACCELERATED_DATABASE_RECOVERY = ON;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET MULTI_USER;
GO
USE texasrangerswillwinitthisyear;
GO

-- Confirm PVS is now truly empty
-- Need to wait for cleaner to finish and evict cached pages before this returns 0
SELECT COUNT(*) AS PVS_Record_Count
FROM sys.dm_tran_persistent_version_store;
GO


USE master;
GO
ALTER DATABASE eaglesdontfly SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
ALTER DATABASE eaglesdontfly SET ACCELERATED_DATABASE_RECOVERY = ON;
ALTER DATABASE eaglesdontfly SET READ_COMMITTED_SNAPSHOT ON;
ALTER DATABASE eaglesdontfly SET ALLOW_SNAPSHOT_ISOLATION ON;
ALTER DATABASE eaglesdontfly SET MULTI_USER;
GO

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- SESSION 1 — Step 2: Open snapshot in texasrangerswillwinitthisyear
--                      This pins the INSTANCE-WIDE XTS watermark
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
USE texasrangerswillwinitthisyear;
GO
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRAN;
    SELECT TOP 1 Id FROM dbo.BigTable;
    -- Snapshot is now established — global XTS floor is pinned
GO

-- TALKING POINT: "I've opened a snapshot in texasrangerswillwinitthisyear.
-- This pins the instance-wide XTS watermark. Now switch to session 2 —
-- we'll generate versions in eaglesdontfly (a completely different database)
-- and try to clean them up."

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- >>> SWITCH TO SESSION 2 (demo4c-session2.sql) <<<
-- >>> Run session 2 through Step 5 <<<
-- >>> Then come back here to release the snapshot <<<
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- SESSION 1 — Step 3: Release the snapshot — XTS floor advances
-- (Run this AFTER session 2 has shown the blocked results)
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
COMMIT;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

-- TALKING POINT: "Snapshot released. The global XTS floor can advance now.
-- Switch back to session 2 to force cleanup — eaglesdontfly should drain."

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- >>> SWITCH BACK TO SESSION 2 to run the final cleanup steps <<<
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

-- ============================================================================
-- SUMMARY
-- ============================================================================
-- TALKING POINT: "The PVS Cleaner is:
-- * Async — runs on a ~60-second timer, not inline with your DML
-- * Background — separate thread(s), lower scheduling priority
-- * Page-level — partially-filled cached pages stay until full or ADR disabled
-- * Instance-wide XTS — a snapshot in ANY database pins cleanup for ALL databases
-- * Observable — dm_tran_persistent_version_store_stats shows everything
--   (check pvs_off_row_page_skipped_min_useful_xts for XTS-pinned cleanup)
-- * The same mechanism that drives Index Compaction in SQL Server 2025
--
-- So what does PVS give you over tempdb version store?
-- * STORAGE isolation — versions live in your own filegroup, not shared tempdb
-- * No tempdb contention — no GAM/SGAM/PFS bottleneck from version store
-- * Faster recovery — versions survive restart, no need to rebuild tempdb
-- * But the cleanup WATERMARK has a global XTS component — same as tempdb
--
-- SQL Server 2022+ also lets you add more cleaner threads via
-- sp_configure 'ADR Cleaner Thread Count'. One thread per ADR-enabled
-- database. Dynamic — no restart. The threads parallelize across
-- databases, not within a database. For a single database, leave it at 1.
--
-- If someone tells you PVS cleanup is broken, it's almost never the
-- cleaner — it's a watermark holder. Find the holder, fix the holder.
-- Use dm_tran_active_snapshot_database_transactions to find who's pinning."
GO
