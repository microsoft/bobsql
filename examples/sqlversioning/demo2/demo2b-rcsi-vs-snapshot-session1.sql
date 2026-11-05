-- ============================================================================
-- DEMO 2b — SESSION 1 (left window): RCSI vs Snapshot
-- Statement-Level vs Transaction-Level consistency
--
-- Load this in SSMS Session 1 (left window).
-- Load demo2b-rcsi-vs-snapshot-session2.sql in Session 2 (right window).
-- ============================================================================
USE texasrangerswillwinitthisyear;
GO

-- Enable RCSI and Snapshot Isolation
ALTER DATABASE texasrangerswillwinitthisyear SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET ALLOW_SNAPSHOT_ISOLATION ON;
GO

-- TALKING POINT: "RCSI gives you a fresh snapshot per statement. Snapshot 
-- Isolation freezes the entire transaction. Let me prove it."

-- Set AccountId = 200 to a known value
UPDATE dbo.Accounts SET Balance = 1000.00 WHERE AccountId = 200;
GO

-- ============================================================================
-- RCSI behavior (statement-level)
-- ============================================================================

-- Start a transaction under RCSI (which is already ON)
BEGIN TRAN;
    -- First read: see Balance = 1000
    SELECT AccountId, Balance FROM dbo.Accounts WHERE AccountId = 200;
GO

-- >>> Go to Session 2: run the RCSI UPDATE (changes Balance to 2000)

-- Second read in the SAME transaction:
    SELECT AccountId, Balance FROM dbo.Accounts WHERE AccountId = 200;
    -- ^^^ Returns Balance = 2000! RCSI got a FRESH snapshot for this statement.
COMMIT;
GO

-- TALKING POINT: "Same transaction, two SELECTs, different results. RCSI
-- refreshes the snapshot for each statement. That's statement-level 
-- consistency — great for OLTP, but you can get non-repeatable reads."

-- ============================================================================
-- Snapshot behavior (transaction-level)
-- ============================================================================

-- Reset
UPDATE dbo.Accounts SET Balance = 1000.00 WHERE AccountId = 200;
GO

-- Start a SNAPSHOT transaction
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRAN;
    -- First read: see Balance = 1000
    SELECT AccountId, Balance FROM dbo.Accounts WHERE AccountId = 200;
GO

-- >>> Go to Session 2: run the Snapshot UPDATE (changes Balance to 2000)

-- Second read in the SAME transaction:
    SELECT AccountId, Balance FROM dbo.Accounts WHERE AccountId = 200;
    -- ^^^ Returns Balance = 1000! Snapshot kept the ORIGINAL snapshot.
COMMIT;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

-- TALKING POINT: "Same scenario, but with Snapshot Isolation — both reads
-- return 1000. The transaction sees data as of BEGIN TRAN, period. 
-- Repeatable reads, guaranteed. But there's a cost..."
