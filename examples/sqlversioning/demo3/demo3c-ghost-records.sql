-- ============================================================================
-- DEMO 3c — Ghost Records vs Version Records (Part 3: Internals)
-- 
-- DELETE under versioning creates BOTH a ghost record AND a version record.
-- Two separate cleanup processes. Neither waits for the other.
-- Self-contained: only requires demo0 (database + tables + data).
-- ============================================================================
USE texasrangerswillwinitthisyear;
GO

-- ============================================================================
-- SETUP: Enable RCSI + Snapshot, ensure ADR and OL are OFF (tempdb versioning)
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

-- TALKING POINT: "When you DELETE a row under versioning, TWO things happen.
-- The old row becomes a version record in the version store. And the row 
-- on the data page becomes a ghost record — marked for deletion but not 
-- yet physically removed. Two separate background processes clean these up."

-- Step 1: Check ghost record count before
SELECT 
    OBJECT_NAME(object_id) AS TableName,
    index_id,
    ghost_record_count,
    version_ghost_record_count,
    record_count
FROM sys.dm_db_index_physical_stats(
    DB_ID(N'texasrangerswillwinitthisyear'), 
    OBJECT_ID(N'dbo.Accounts'), 
    1, NULL, 'DETAILED')
WHERE index_level = 0;
GO

-- Step 2: Start a snapshot to hold versions, then DELETE rows
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRAN;
    SELECT TOP 1 AccountId FROM dbo.Accounts;  -- establish snapshot
GO

-- Session 2: delete 100 rows
DELETE FROM dbo.Accounts WHERE AccountId BETWEEN 9901 AND 10000;
GO

-- Step 3: Now check — we should see BOTH ghost records AND version store growth
SELECT 
    OBJECT_NAME(object_id) AS TableName,
    ghost_record_count,
    version_ghost_record_count
FROM sys.dm_db_index_physical_stats(
    DB_ID(N'texasrangerswillwinitthisyear'), 
    OBJECT_ID(N'dbo.Accounts'), 
    1, NULL, 'DETAILED')
WHERE index_level = 0;
GO

SELECT 
    DB_NAME(database_id) AS [Database],
    reserved_page_count  AS VersionPages,
    reserved_space_kb    AS VersionSpaceKB
FROM sys.dm_tran_version_store_space_usage
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- TALKING POINT: "See both numbers? Ghost records on the data page — those 
-- are the deleted rows still physically present. Version store in tempdb — 
-- those are the before-images kept for our snapshot reader.
--
-- Ghost cleanup and version cleanup are INDEPENDENT processes:
--   • Ghost cleaner: runs on a timer, removes ghost records from data pages
--   • Version cleaner: runs on a timer, removes old versions from tempdb
-- Neither waits for the other. A DELETE under versioning triggers both."

-- Step 4: Commit the snapshot and let both cleaners run
COMMIT;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

-- Re-check after a few seconds — both should decrease
SELECT 
    OBJECT_NAME(object_id) AS TableName,
    ghost_record_count,
    version_ghost_record_count
FROM sys.dm_db_index_physical_stats(
    DB_ID(N'texasrangerswillwinitthisyear'), 
    OBJECT_ID(N'dbo.Accounts'), 
    1, NULL, 'DETAILED')
WHERE index_level = 0;
GO

SELECT 
    DB_NAME(database_id) AS [Database],
    reserved_page_count  AS VersionPages,
    reserved_space_kb    AS VersionSpaceKB
FROM sys.dm_tran_version_store_space_usage
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- Re-seed the deleted rows for later demos
INSERT INTO dbo.Accounts (AccountName, Balance, Status)
SELECT
    N'Account_' + CAST(v.n + 9900 AS NVARCHAR(10)),
    CAST(ABS(CHECKSUM(NEWID())) % 100000 AS DECIMAL(18,2)) / 100.0,
    N'Active'
FROM (
    SELECT TOP (100) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects
) v;
GO
