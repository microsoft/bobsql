-- ============================================================================
-- DEMO 2c — SESSION 1 (left window): Snapshot Update Conflict
-- Error 3960 — optimistic concurrency failure
--
-- Load this in SSMS Session 1 (left window).
-- Load demo2c-snapshot-conflict-session2.sql in Session 2 (right window).
-- ============================================================================
USE texasrangerswillwinitthisyear;
GO

-- ============================================================================
-- SETUP: Enable RCSI + Snapshot
-- ============================================================================
ALTER DATABASE texasrangerswillwinitthisyear SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET ALLOW_SNAPSHOT_ISOLATION ON;
GO

-- TALKING POINT: "Snapshot gives you repeatable reads without locks. The 
-- tradeoff? If two writers hit the same row, the second one loses."

-- Reset
UPDATE dbo.Accounts SET Balance = 100.00 WHERE AccountId = 100;
GO

-- Start a Snapshot transaction and read AccountId = 100
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRAN;
    SELECT AccountId, Balance FROM dbo.Accounts WHERE AccountId = 100;
GO

-- >>> Go to Session 2: modify the same row and COMMIT.

-- Try to update the same row — ERROR 3960:
UPDATE dbo.Accounts 
SET Balance = Balance + 50.00 
WHERE AccountId = 100;
-- ^^^ ERROR: Msg 3960, Level 16, State 2
-- "Snapshot isolation transaction aborted due to update conflict."
GO

-- TALKING POINT: "Error 3960. Snapshot Isolation uses optimistic concurrency.
-- Two writers, same row — the second one loses. Your app must catch this
-- and retry. RCSI does NOT have this behavior — only Snapshot Isolation."

-- Error 3960 automatically aborts and rolls back the transaction.
-- Just reset the isolation level back to READ COMMITTED.
IF @@TRANCOUNT > 0 ROLLBACK;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

-- Reset
UPDATE dbo.Accounts SET Balance = 100.00 WHERE AccountId = 100;
GO
