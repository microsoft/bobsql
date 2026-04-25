-- ============================================================================
-- DEMO 3b — SESSION 1: The forgotten snapshot in eaglesdontfly
-- Version Store Growth + Instance-Wide Impact
--
-- Load this in SSMS Session 1.
-- Load demo3b-instance-wide-impact-session2.sql in Session 2.
--
-- Prerequisites: Run demo0-setup.sql first (creates eaglesdontfly +
--   howboutthemcowboys databases).
-- ============================================================================

-- ============================================================================
-- VERIFY PREREQUISITES
-- ============================================================================
IF DB_ID(N'eaglesdontfly') IS NULL OR DB_ID(N'howboutthemcowboys') IS NULL
BEGIN
    RAISERROR(N'Missing databases. Run demo0-setup.sql first.', 16, 1);
    SET NOEXEC ON;
END
GO

-- ────────────────────────────────────────────────────────────────────────────
-- SETUP: Ensure RCSI + Snapshot ON, ADR + OL OFF for both databases
-- ────────────────────────────────────────────────────────────────────────────
ALTER DATABASE eaglesdontfly SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
ALTER DATABASE eaglesdontfly SET ALLOW_SNAPSHOT_ISOLATION ON;
GO
ALTER DATABASE howboutthemcowboys SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
ALTER DATABASE howboutthemcowboys SET ALLOW_SNAPSHOT_ISOLATION ON;
GO

-- ────────────────────────────────────────────────────────────────────────────
-- BASELINE: Everything is clean
-- ────────────────────────────────────────────────────────────────────────────
USE tempdb;
GO
SELECT 
    SUM(version_store_reserved_page_count) AS VersionStorePages,
    SUM(version_store_reserved_page_count) * 8 AS VersionStoreKB,
    SUM(total_page_count) AS TotalPages
FROM sys.dm_db_file_space_usage;
GO

SELECT 
    DB_NAME(database_id) AS [Database],
    reserved_page_count  AS VersionPages,
    reserved_space_kb    AS VersionSpaceKB
FROM sys.dm_tran_version_store_space_usage
WHERE database_id IN (DB_ID(N'eaglesdontfly'), DB_ID(N'howboutthemcowboys'))
ORDER BY reserved_page_count DESC;
GO

-- TALKING POINT: "Clean slate. Version store near zero. Two databases —
-- eaglesdontfly and howboutthemcowboys — both have RCSI and Snapshot on.
-- Now let's simulate a production incident."

-- ============================================================================
-- THE FORGOTTEN SNAPSHOT — Open a snapshot and leave it
-- ============================================================================
SELECT @@SPID AS [Session 1 SPID — the forgotten app];
GO

USE eaglesdontfly;
GO
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRAN;
    -- App reads one row for a report... then hangs. Transaction stays open.
    SELECT TOP 1 Category, SuperBowlChances FROM dbo.ReportData;
    -- DO NOT COMMIT — this pins the cleanup watermark for the ENTIRE INSTANCE
GO

-- TALKING POINT: "One SELECT. One row. The app is done reading — but the
-- transaction is still open. This session's XSN is now the oldest active 
-- snapshot. The version cleaner cannot remove ANY version newer than this."

-- >>> Go to Session 2: run the UPDATE waves in howboutthemcowboys.
-- >>> Come back here after all waves + diagnostics are done.

-- ============================================================================
-- THE FIX — Commit the forgotten transaction
-- ============================================================================

-- >>> After Session 2 has shown the damage:
USE eaglesdontfly;
GO
COMMIT;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

-- TALKING POINT: "In production you'd KILL that session. The DBA might not 
-- even know which app it is. But the moment it's gone, the watermark 
-- advances and the cleaner can work."

-- ────────────────────────────────────────────────────────────────────────────
-- Verify cleanup (wait ~60s for the background cleaner)
-- ────────────────────────────────────────────────────────────────────────────

USE tempdb;
GO
SELECT 
    SUM(version_store_reserved_page_count) AS VersionStorePages,
    SUM(version_store_reserved_page_count) * 8 AS VersionStoreKB,
    SUM(total_page_count) AS TotalPages
FROM sys.dm_db_file_space_usage;
GO

SELECT 
    DB_NAME(database_id) AS [Database],
    reserved_page_count  AS VersionPages,
    reserved_space_kb    AS VersionSpaceKB
FROM sys.dm_tran_version_store_space_usage
WHERE database_id IN (DB_ID(N'eaglesdontfly'), DB_ID(N'howboutthemcowboys'));
GO

SELECT * FROM sys.dm_tran_active_snapshot_database_transactions;
GO

-- TALKING POINT: "Version store dropped back to near zero. The cleaner 
-- swept everything in one pass. But look at tempdb file size — TotalPages 
-- didn't shrink. The pages are freed internally, but the file on disk 
-- keeps its high-water mark. Only a SQL Server restart resets tempdb."
