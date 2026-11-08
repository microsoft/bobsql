-- ============================================================================
-- DEMO 2a — SESSION 2 (right window): The Reader with RCSI
-- RCSI — the right fix for blocking
--
-- Load this in SSMS Session 2 (right window).
-- Load demo2a-rcsi-session1.sql in Session 1 (left window).
-- ============================================================================
USE texasrangerswillwinitthisyear;
GO

-- ============================================================================
-- PART 1: RCSI read — no blocking, no dirty read
-- ============================================================================

-- >>> Session 1 has started a transaction and holds an X lock.
-- Returns IMMEDIATELY with the pre-UPDATE value:
SELECT AccountId, AccountName, Balance
FROM dbo.Accounts
WHERE AccountId = 1;
-- ^^^ Instant. No blocking. Shows the old (committed) balance = 100.
GO

-- TALKING POINT: "No wait. No dirty read. The reader got the last committed
-- version of the row. The writer can take as long as it wants — readers
-- don't care. That's RCSI."

-- Show the version store is being used:
SELECT 
    DB_NAME(database_id) AS [Database],
    reserved_page_count  AS VersionPages,
    reserved_space_kb    AS VersionSpaceKB
FROM sys.dm_tran_version_store_space_usage
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- ============================================================================
-- PART 2: READCOMMITTEDLOCK — the escape hatch
-- ============================================================================
-- TALKING POINT: "RCSI is database-wide. But what if one specific query 
-- needs the old lock-based behavior?"

-- >>> Session 1 STILL has the X lock held.
-- Same query, add the hint — blocks:
SELECT AccountId, AccountName, Balance
FROM dbo.Accounts WITH (READCOMMITTEDLOCK)
WHERE AccountId = 1;
-- ^^^ BLOCKED! The hint forces traditional S-lock READ COMMITTED.
GO

-- TALKING POINT: "READCOMMITTEDLOCK overrides RCSI for that one query.
-- There's no per-query hint to turn RCSI ON — it's all-or-nothing at the
-- database level. But you can opt out per-query if you have to."

-- >>> Go back to Session 1: COMMIT to release.
