-- ============================================================================
-- DEMO 3a — SESSION 2 (right window): The Writer
-- Inside the Version Chain — RCSI and Snapshot
--
-- Load this in SSMS Session 2 (right window).
-- Load demo3a-version-chain-session1.sql in Session 1 (left window).
-- ============================================================================
USE texasrangerswillwinitthisyear;
GO

-- ============================================================================
-- BEAT 1: RCSI — Single version
-- ============================================================================

SELECT @@SPID AS MySessionId;
GO

-- >>> Session 1 has read AccountId 42. Now update it (don't commit):
BEGIN TRAN;
    UPDATE dbo.Accounts 
    SET Balance = 200.00, LastUpdated = SYSUTCDATETIME() 
    WHERE AccountId = 42;
    -- Balance is now 200 on the page — but NOT committed.
    -- The before-image (old Balance) was written to the version store.
    -- DO NOT COMMIT
GO

-- DMV confirmation — version store has one record:
SELECT 
    transaction_sequence_num AS XSN,
    version_sequence_num     AS SeqInChain,
    DB_NAME(database_id)     AS [Database],
    database_id, rowset_id, status, min_length_in_bytes,
    record_length_first_part_in_bytes AS RecordBytes1st,
    record_image_first_part
FROM sys.dm_tran_version_store
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear');
GO

-- >>> Go to Session 1: read under RCSI — sees the old Balance.

-- Commit:
SELECT @@SPID AS MySessionId;
GO
COMMIT;
GO

-- >>> Go to Session 1: read again — now sees 200. 
-- >>> Wait ~60s, verify cleanup.

-- ============================================================================
-- BEAT 2: Snapshot — Three committed updates (builds a 3-link chain)
-- ============================================================================

-- >>> Session 1 has opened a SNAPSHOT transaction (anchored at Balance = 200).
-- Now do 3 updates. Each generates a version record.

SELECT @@SPID AS MySessionId;
GO

-- Update #1: 200 → 300
UPDATE dbo.Accounts 
SET Balance = 300.00, LastUpdated = SYSUTCDATETIME() 
WHERE AccountId = 42;
GO

-- Update #2: 300 → 400
UPDATE dbo.Accounts 
SET Balance = 400.00, LastUpdated = SYSUTCDATETIME() 
WHERE AccountId = 42;
GO

-- Update #3: 400 → 500
UPDATE dbo.Accounts 
SET Balance = 500.00, LastUpdated = SYSUTCDATETIME() 
WHERE AccountId = 42;
GO

-- DMV shows 3 version records:
SELECT 
    transaction_sequence_num AS XSN,
    version_sequence_num     AS SeqInChain,
    DB_NAME(database_id)     AS [Database],
    database_id, rowset_id, status, min_length_in_bytes,
    record_length_first_part_in_bytes AS RecordBytes1st,
    record_image_first_part
FROM sys.dm_tran_version_store
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear')
ORDER BY transaction_sequence_num DESC;
GO

-- TALKING POINT: "Three version records — the chain is:
-- 500 (page) → 400 → 300 → 200 (end of chain). 
-- Our Snapshot reader at 200 must walk all 3 hops to get there."

-- >>> Go back to Session 1: read under Snapshot — sees 200 after 3 hops.
