-- ============================================================================
-- DEMO 3a — SESSION 1 (left window): The Reader / Snapshot holder
-- Inside the Version Chain — RCSI and Snapshot
--
-- Load this in SSMS Session 1 (left window).
-- Load demo3a-version-chain-session2.sql in Session 2 (right window).
--
-- Prerequisites:
--   1. demo0-setup.sql has been run
--   2. Flask page viewer running: python demos/dbcc_page_viewer.py
--   3. Browser open to http://localhost:5050
-- ============================================================================
USE texasrangerswillwinitthisyear;
GO

-- ============================================================================
-- SETUP: Enable required isolation levels
-- ============================================================================
ALTER DATABASE texasrangerswillwinitthisyear SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET READ_COMMITTED_SNAPSHOT ON;
ALTER DATABASE texasrangerswillwinitthisyear SET ALLOW_SNAPSHOT_ISOLATION ON;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET MULTI_USER;
GO

-- ============================================================================
-- BEAT 1: RCSI — Version Created, Page-Level Proof, Version Cleaned
-- ============================================================================

-- TALKING POINT: "Let's look inside the version store. When a row is 
-- modified under RCSI, the engine saves the before-image. Let me show you
-- at every level — the SQL result, the data page, and the version store."

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  >>> BROWSER: Enter 42 in "Find Row (AccountId)", click View Page.     ║
-- ║  >>> Note the Balance value — this is what will become the version.    ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

SELECT @@SPID AS MySessionId;
GO
SELECT AccountId, AccountName, Balance FROM dbo.Accounts WHERE AccountId = 42;
-- ^^^ Whatever the current Balance is. Committed value, no version needed.
GO

-- >>> Go to Session 2: UPDATE AccountId 42 (don't commit).

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  >>> BROWSER: Click View Page (refresh).                               ║
-- ║  >>> Audience sees:                                                    ║
-- ║  >>>   - Balance = 200.00 on the data page (uncommitted new value)     ║
-- ║  >>>   - 14-Byte Version Tag appeared in orange — XSN + pointer        ║
-- ║  >>>   - Version Store section: decoded record showing the OLD Balance ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Read under RCSI (walks the version chain):
SELECT @@SPID AS MySessionId;
GO
SELECT AccountId, Balance FROM dbo.Accounts WHERE AccountId = 42;
-- ^^^ The OLD Balance — not 200. The engine walked the version chain.
GO

-- TALKING POINT: "RCSI read returns the old Balance. The engine walked from
-- the data page → version tag → tempdb → before-image. One hop."

-- >>> Go to Session 2: COMMIT.

-- Read again (now sees 200):
SELECT @@SPID AS MySessionId;
GO
SELECT AccountId, Balance FROM dbo.Accounts WHERE AccountId = 42;
-- ^^^ Balance = 200. The committed value.
GO

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  >>> BROWSER: Click View Page.                                         ║
-- ║  >>> Version tag still on the row. Version store will clear ~60s.      ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- TALKING POINT: "Committed. The version tag stays on the row forever — 
-- SQL Server doesn't reclaim those 14 bytes. But the version store record 
-- in tempdb? The cleaner will remove it because nobody needs it anymore."

-- Wait ~60 seconds (talk through a slide), then verify cleanup
SELECT 
    transaction_sequence_num AS XSN,
    version_sequence_num     AS SeqInChain,
    DB_NAME(database_id)     AS [Database],
    database_id, rowset_id, status, min_length_in_bytes,
    record_length_first_part_in_bytes AS RecordBytes1st,
    record_image_first_part
FROM sys.dm_tran_version_store
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
-- ^^^ Empty — cleaner removed it.
GO

-- TALKING POINT: "Gone. Versions are always generated under RCSI, but
-- they don't pile up unless someone holds them. Now let me show you
-- what 'holding' looks like."

-- ============================================================================
-- BEAT 2: Snapshot — Version Chain Held, 3 Hops, NOT Cleaned
-- ============================================================================

-- TALKING POINT: "Under Snapshot Isolation, the reader locks in a 
-- point-in-time at BEGIN TRAN. That anchors the version store watermark —
-- versions can't be cleaned until the snapshot commits."

-- Open a SNAPSHOT transaction (anchors the watermark):
SELECT @@SPID AS MySessionId;
GO
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRAN;
    SELECT AccountId, Balance FROM dbo.Accounts WHERE AccountId = 42;
    -- ^^^ Balance = 200. This is our snapshot point-in-time. DO NOT COMMIT.
GO

-- TALKING POINT: "Our snapshot is locked in. The engine captured an internal
-- timestamp (XTS). For each row it reads, it asks: 'did the writer commit 
-- before my snapshot?' That's the visibility decision."

-- >>> Go to Session 2: run the 3 UPDATEs (200 → 300 → 400 → 500).

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  >>> BROWSER: Click View Page.                                         ║
-- ║  >>> Audience sees: Balance = 500, version chain with 3 records        ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Check chain traversal BEFORE the read:
SELECT 
    max_version_chain_traversed   AS MaxChainHops_Before,
    average_version_chain_traversed AS AvgChainHops_Before
FROM sys.dm_tran_active_snapshot_database_transactions
WHERE session_id = @@SPID;
GO

-- Read under Snapshot (walks 3 hops):
SET STATISTICS IO ON;
GO
SELECT AccountId, Balance FROM dbo.Accounts WHERE AccountId = 42;
-- ^^^ Balance = 200! Not 500.
-- STATISTICS IO shows 2 logical reads — the extra read is the cost of
-- version chain traversal (vs 1 logical read under plain READ COMMITTED).
GO
SET STATISTICS IO OFF;
GO

-- Check chain traversal AFTER the read:
SELECT 
    max_version_chain_traversed   AS MaxChainHops_After,
    average_version_chain_traversed AS AvgChainHops_After
FROM sys.dm_tran_active_snapshot_database_transactions
WHERE session_id = @@SPID;
GO

-- TALKING POINT: "STATISTICS IO says 2 logical reads — 1 extra vs plain
-- READ COMMITTED. And look at MaxChainHops: it jumped from 0 to 3. Those 
-- are 3 hops through tempdb's version store that STATISTICS IO doesn't 
-- break out separately."

-- Version store space — held by our snapshot:
SELECT 
    DB_NAME(database_id) AS [Database],
    reserved_page_count  AS VersionPages,
    reserved_space_kb    AS VersionSpaceKB
FROM sys.dm_tran_version_store_space_usage
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- Who's holding the watermark?
SELECT 
    session_id,
    transaction_id,
    elapsed_time_seconds,
    max_version_chain_traversed       AS MaxChainHops,
    average_version_chain_traversed   AS AvgChainHops
FROM sys.dm_tran_active_snapshot_database_transactions;
GO

-- TALKING POINT: "This DMV shows who's holding versions hostage and for
-- how long. In production, this is the first DMV you check when tempdb 
-- version store is growing."

-- Commit to release the watermark:
COMMIT;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO
