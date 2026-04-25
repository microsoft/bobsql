-- ============================================================================
-- DEMO 3b — SESSION 2: Normal OLTP in howboutthemcowboys
-- Version Store Growth + Instance-Wide Impact
--
-- Load this in SSMS Session 2.
-- Load demo3b-instance-wide-impact-session1.sql in Session 1.
--
-- Prerequisites: Run demo0-setup.sql first.
-- ============================================================================

-- Reset GameStats rows to a clean baseline
USE howboutthemcowboys;
GO

SELECT @@SPID AS [Session 2 SPID — normal OLTP];
GO

-- >>> Session 1 has opened a forgotten snapshot in eaglesdontfly.

-- ════════════════════════════════════════════════════════════════════════════
-- 💾 POINT 1: tempdb grows from normal OLTP
--
-- Each wave updates ALL 5000 rows. Every row is 7KB (1 per page), so every
-- version record is ~7KB.  5 waves = ~175 MB stuck in tempdb.
-- ════════════════════════════════════════════════════════════════════════════

-- Wave 1
UPDATE dbo.GameStats SET Yards = Yards + 1;
GO
-- Wave 2
UPDATE dbo.GameStats SET Yards = Yards + 1;
GO
-- Wave 3
UPDATE dbo.GameStats SET Yards = Yards + 1;
GO
-- Wave 4
UPDATE dbo.GameStats SET Yards = Yards + 1;
GO
-- Wave 5
UPDATE dbo.GameStats SET Yards = Yards + 1;
GO

-- How much did tempdb grow?
USE tempdb;
GO
SELECT 
    SUM(version_store_reserved_page_count) AS VersionStorePages,
    SUM(version_store_reserved_page_count) * 8 AS VersionStoreKB
FROM sys.dm_db_file_space_usage;
GO

-- TALKING POINT: "5 waves × 5,000 wide rows. Each version is ~7KB — one
-- per tempdb page. That's ~175 MB of versions stuck in tempdb. The cleaner 
-- runs every 60 seconds but can't touch any of it."

-- ════════════════════════════════════════════════════════════════════════════
-- 💥 POINT 2: Cross-database collateral damage
-- ════════════════════════════════════════════════════════════════════════════

-- WHERE is the version store space?
SELECT 
    DB_NAME(database_id) AS [Database],
    reserved_page_count  AS VersionPages,
    reserved_space_kb    AS VersionSpaceKB
FROM sys.dm_tran_version_store_space_usage
WHERE reserved_page_count > 0
ORDER BY reserved_page_count DESC;
GO

-- TALKING POINT: "Look — howboutthemcowboys is the biggest consumer.
-- But howboutthemcowboys didn't open any snapshot transaction!
-- The versions are from normal OLTP. So who's blocking cleanup?"

-- ════════════════════════════════════════════════════════════════════════════
-- 🔍 POINT 3: Who is holding the watermark?
-- ════════════════════════════════════════════════════════════════════════════

SELECT 
    t.session_id,
    DB_NAME(s.database_id)  AS [Session Database],
    t.elapsed_time_seconds,
    CAST(t.elapsed_time_seconds / 60.0 AS DECIMAL(10,1)) AS elapsed_minutes
FROM sys.dm_tran_active_snapshot_database_transactions t
JOIN sys.dm_exec_sessions s ON s.session_id = t.session_id;
GO

-- TALKING POINT: "There it is. One session — from eaglesdontfly — sitting 
-- idle with a forgotten snapshot. Its watermark is the oldest on the 
-- instance. The cleaner can't touch ANY version — not even the Cowboys'."

-- ════════════════════════════════════════════════════════════════════════════
-- 📈 POINT 4: Damage is non-linear (more waves = more space)
-- ════════════════════════════════════════════════════════════════════════════

USE howboutthemcowboys;
GO

-- 5 MORE waves — version store doubles
UPDATE dbo.GameStats SET Yards = Yards + 1;
GO
UPDATE dbo.GameStats SET Yards = Yards + 1;
GO
UPDATE dbo.GameStats SET Yards = Yards + 1;
GO
UPDATE dbo.GameStats SET Yards = Yards + 1;
GO
UPDATE dbo.GameStats SET Yards = Yards + 1;
GO

-- Check growth AGAIN
USE tempdb;
GO
SELECT 
    SUM(version_store_reserved_page_count) AS VersionStorePages,
    SUM(version_store_reserved_page_count) * 8 AS VersionStoreKB
FROM sys.dm_db_file_space_usage;
GO

SELECT 
    DB_NAME(database_id) AS [Database],
    reserved_page_count  AS VersionPages,
    reserved_space_kb    AS VersionSpaceKB
FROM sys.dm_tran_version_store_space_usage
WHERE reserved_page_count > 0
ORDER BY reserved_page_count DESC;
GO

-- TALKING POINT: "It doubled. ~175MB → ~350MB. In production with 100 
-- threads running DML for 2 hours — that's how tempdb fills a 500GB drive."

-- >>> Go back to Session 1: COMMIT the forgotten snapshot (THE FIX).

-- ════════════════════════════════════════════════════════════════════════════
-- ✅ POINT 5: After the fix — version store cleans up
-- ════════════════════════════════════════════════════════════════════════════

-- >>> Wait ~60s for the cleaner, then:

SELECT 
    SUM(version_store_reserved_page_count) AS VersionStorePages,
    SUM(version_store_reserved_page_count) * 8 AS VersionStoreKB
FROM sys.dm_db_file_space_usage;
GO

SELECT 
    DB_NAME(database_id) AS [Database],
    reserved_page_count  AS VersionPages,
    reserved_space_kb    AS VersionSpaceKB
FROM sys.dm_tran_version_store_space_usage
WHERE reserved_page_count > 0
ORDER BY reserved_page_count DESC;
GO

-- TALKING POINT: "Version store is back to zero. One COMMIT freed ~350MB.
-- But tempdb file size didn't shrink — the pages are freed internally, 
-- but the file on disk stays. That's why tempdb autogrow from version 
-- store bloat is permanent until you restart SQL Server.
--
-- This is why PVS matters: with Persistent Version Store, each database 
-- manages its own versions. eaglesdontfly's forgotten transaction would 
-- only hurt eaglesdontfly — the Cowboys would be fine."
