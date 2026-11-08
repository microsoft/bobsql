-- ============================================================================
-- DEMO 4b — SESSION 2 (right window): Direct Off-Row — The Writer
-- Wide column update that goes straight to PVS (no in-row step).
--
-- Load this in SSMS Session 2 (right window).
-- Load demo4b-adr-offrow-versioning-session1.sql in Session 1 (left window).
-- ============================================================================
USE texasrangerswillwinitthisyear;
GO

-- ============================================================================
-- Direct Off-Row — Wide Column Goes Straight to PVS
-- ============================================================================

SELECT @@SPID AS MySessionId;
GO

-- >>> Session 1 has started a SNAPSHOT transaction and read SavingsAccounts 42.

-- Single UPDATE: wide column change → direct off-row PVS.
-- ComplianceNotes is CHAR(600). The diff payload (~600 bytes) exceeds the
-- 200-byte in-row limit, so the engine writes straight to a PVS page.
-- No in-row step, no promotion — off-row from the start.
UPDATE dbo.SavingsAccounts 
SET Balance = 999.99, 
    LastUpdated = SYSUTCDATETIME(),
    ComplianceNotes = 'UPDATED: Phase 1 compliance review completed. Enhanced due diligence performed per quarterly review cycle. AML screening passed. Customer documentation re-verified and archived. Risk assessment score updated to reflect current credit profile and transaction patterns.'
WHERE AccountId = 42;
GO

-- Show the PVS record that was just created:
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
    WHERE o.name = N'SavingsAccounts' AND p.index_id IN (0,1));
GO

-- TALKING POINT: "There it is — the PVS record. The record_image contains
-- the before-image of the row. The engine wrote ~600 bytes of diff payload
-- directly to this PVS page. No in-row step — it went straight off-row."

-- TALKING POINT: "One update, but the diff is ~600 bytes — way over the
-- 200-byte in-row limit. The engine skipped in-row entirely and wrote
-- the before-image directly to a PVS page. The page viewer shows
-- slot >= 0 (off-row pointer) after just one update."

-- >>> Go to Session 1: refresh page viewer — off-row immediately, no chain.
-- >>> Read under SNAPSHOT — gets original. End SNAPSHOT, wrap up.
