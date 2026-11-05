-- ============================================================================
-- DEMO 4a — SESSION 2 (right window): ADR Versioning — The Writer
-- Shows how ADR generates versions in PVS for recovery, and how RCSI
-- lets readers use those same versions. Then in-row vs off-row PVS.
--
-- Load this in SSMS Session 2 (right window).
-- Load demo4a-adr-versioning-session1.sql in Session 1 (left window).
-- ============================================================================
USE texasrangerswillwinitthisyear;
GO

-- ============================================================================
-- BEAT 0: ADR ON, RCSI OFF — versions exist but readers block
-- ============================================================================

SELECT @@SPID AS MySessionId;
GO

-- >>> Session 1 has ADR ON, RCSI OFF. Update AccountId 42 (don't commit):

-- First, capture the current values so we can verify the page viewer's
-- BEFORE-IMAGE decoding after the update:
SELECT AccountId, Balance, LastUpdated FROM dbo.Accounts WHERE AccountId = 42;
GO

BEGIN TRAN;
    UPDATE dbo.Accounts 
    SET Balance = 200.00, LastUpdated = SYSUTCDATETIME() 
    WHERE AccountId = 42;
    -- ADR generated a version for recovery — stored as an in-row diff
    -- on the data page (narrow change). But Session 1's reader under 
    -- plain READ COMMITTED will BLOCK.
    -- DO NOT COMMIT
GO

-- TALKING POINT: "ADR created a version — you can see it in the page viewer.
-- It's an in-row version stub because the change was narrow (just Balance).
-- Note: persistent_version_store_size_kb won't show it — that DMV only
-- tracks off-row PVS pages. In-row stubs live on the data page itself.
-- But Session 1 is blocked — plain READ COMMITTED doesn't use versions."

-- >>> Go to Session 1: try to read (it blocks). Show the page viewer.

-- Rollback so we can re-enable RCSI
ROLLBACK;
GO

-- >>> Go to Session 1: enable RCSI, then come back here.

-- ============================================================================
-- BEAT 1: SNAPSHOT — In-Row Version → Off-Row Promotion + Chain
-- ============================================================================

SELECT @@SPID AS MySessionId;
GO

-- >>> Session 1 has started a SNAPSHOT transaction and read AccountId 42.

-- UPDATE #1: Balance = 200 → commits immediately (auto-commit).
-- Creates version V1 with original Balance as the before-image.
-- Narrow change → in-row diff on the data page (slot = -4).
UPDATE dbo.Accounts 
SET Balance = 200.00, LastUpdated = SYSUTCDATETIME() 
WHERE AccountId = 42;
GO

-- TALKING POINT: "One auto-committed update. The data page now has an
-- in-row version — a 33-byte diff payload appended directly to the row.
-- The page viewer shows slot = -4, ADR's marker for in-row storage.
-- No PVS page allocated."

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  >>> BROWSER: Click View Page (refresh) NOW.                           ║
-- ║  >>> Audience sees: IN-ROW version stub (slot = -4).                   ║
-- ║  >>>   33-byte diff payload stored directly on the data page.          ║
-- ║  >>>   No PVS page reference — this version lives on the data page.   ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- UPDATE #2: Balance = 300 → also auto-commits.
-- In-row can only hold ONE version. The engine evicts the existing
-- in-row diff to a PVS page and promotes to off-row.
UPDATE dbo.Accounts 
SET Balance = 300.00, LastUpdated = SYSUTCDATETIME() 
WHERE AccountId = 42;
GO

-- Show the PVS record — the evicted version is now off-row:
SELECT 
    pvs.xdes_ts_push AS PushTS,
    pvs.xdes_ts_tran AS TranTS,
    pvs.seq_num AS SeqNum,
    pvs.min_len AS MinLen,
    pvs.rowset_id AS RowsetId,
    pvs.prev_row_in_chain AS PrevRowInChain,
    pvs.row_version AS RowVersion
FROM sys.dm_tran_persistent_version_store AS pvs
WHERE pvs.rowset_id = (SELECT p.hobt_id FROM sys.partitions p 
    JOIN sys.objects o ON p.object_id = o.object_id 
    WHERE o.name = N'Accounts' AND p.index_id IN (0,1));
GO

-- TALKING POINT: "One PVS record. The in-row diff was evicted and the
-- original before-image is embedded in the row_version column — not a 
-- separate PVS row. The page viewer shows slot >= 0 (off-row pointer)."

-- UPDATE #3: Balance = 400 → auto-commits.
-- Now a second PVS record is created. The engine chains them via
-- prev_row_in_chain: new record (stores 300) → existing record (stores 200 + original).
UPDATE dbo.Accounts 
SET Balance = 400.00, LastUpdated = SYSUTCDATETIME() 
WHERE AccountId = 42;
GO

-- Show the PVS chain — now TWO records:
SELECT 
    pvs.xdes_ts_push AS PushTS,
    pvs.xdes_ts_tran AS TranTS,
    pvs.seq_num AS SeqNum,
    pvs.min_len AS MinLen,
    pvs.rowset_id AS RowsetId,
    pvs.prev_row_in_chain AS PrevRowInChain,
    pvs.row_version AS RowVersion
FROM sys.dm_tran_persistent_version_store AS pvs
WHERE pvs.rowset_id = (SELECT p.hobt_id FROM sys.partitions p 
    JOIN sys.objects o ON p.object_id = o.object_id 
    WHERE o.name = N'Accounts' AND p.index_id IN (0,1));
GO

-- TALKING POINT: "NOW we have two PVS records — one for each off-row update.
-- The newest stores Balance=300 (before UPDATE #3). The older one stores the
-- original+200 chain from the in-row eviction. prev_row_in_chain links them."

-- >>> Go to Session 1: refresh page viewer — off-row chain with 2 PVS records.
-- >>> Read under SNAPSHOT — gets original. End SNAPSHOT, verify sees 400.

-- >>> Continue to demo4b-adr-offrow-versioning: Direct off-row versioning with wide columns.
