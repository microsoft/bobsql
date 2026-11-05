-- ============================================================================
-- DEMO 2a — SESSION 1 (left window): The Writer
-- RCSI — the right fix for blocking
--
-- Load this in SSMS Session 1 (left window).
-- Load demo2a-rcsi-session2.sql in Session 2 (right window).
-- ============================================================================
USE texasrangerswillwinitthisyear;
GO

-- Reset key rows to known starting balances for clean demo
UPDATE dbo.Accounts SET Balance = 100.00 WHERE AccountId = 1;
UPDATE dbo.Accounts SET Balance = 100.00 WHERE AccountId = 100;
UPDATE dbo.Accounts SET Balance = 100.00 WHERE AccountId = 200;
GO

-- ============================================================================
-- PART 1: Enable RCSI — the right fix for blocking
-- ============================================================================
-- TALKING POINT: "In Demo 1 we saw blocking and the NOLOCK disaster. 
-- Here's the right fix — one ALTER DATABASE, zero code changes."

ALTER DATABASE texasrangerswillwinitthisyear SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
GO

-- TALKING POINT: "Notice the WITH ROLLBACK IMMEDIATE. This ALTER DATABASE  
-- requires an exclusive database lock — it can't run while other sessions 
-- are connected. Without ROLLBACK IMMEDIATE, it will wait for every active
-- transaction to finish. On a busy production server, that can look like 
-- it's hanging. Plan this for a maintenance window, or use ROLLBACK IMMEDIATE 
-- and accept that active transactions get killed."

SELECT name, is_read_committed_snapshot_on AS RCSI
FROM sys.databases WHERE name = N'texasrangerswillwinitthisyear';
-- Should show RCSI = 1
GO

-- Show the balance BEFORE the update — audience needs this reference point:
SELECT AccountId, AccountName, Balance FROM dbo.Accounts WHERE AccountId = 1;

BEGIN TRAN;
    UPDATE dbo.Accounts
    SET Balance = Balance + 500.00,
        LastUpdated = SYSUTCDATETIME()
    WHERE AccountId = 1;
    -- DO NOT COMMIT — hold the X lock

-- >>> Go to Session 2: run the RCSI SELECT — it returns immediately!

-- Session 1 STILL has the X lock held — do NOT commit yet.

-- >>> Go to Session 2: run the READCOMMITTEDLOCK SELECT — it blocks!

-- Commit to release:
COMMIT;
GO
