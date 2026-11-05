-- ============================================================================
-- DEMO 1 — SESSION 1 (left window): The Writer
-- Part 1: Why Versioning?
--
-- Load this in SSMS Session 1 (left window).
-- Load demo1-blocking-session2.sql in Session 2 (right window).
-- ============================================================================
USE texasrangerswillwinitthisyear;
GO

-- ============================================================================
-- RESET: Clear any options set by later demos so D1 works from a clean state
-- Run this before every practice/presentation to ensure a clean starting point
-- ============================================================================
ALTER DATABASE texasrangerswillwinitthisyear SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET OPTIMIZED_LOCKING = OFF;
ALTER DATABASE texasrangerswillwinitthisyear SET ACCELERATED_DATABASE_RECOVERY = OFF;
ALTER DATABASE texasrangerswillwinitthisyear SET ALLOW_SNAPSHOT_ISOLATION OFF;
ALTER DATABASE texasrangerswillwinitthisyear SET READ_COMMITTED_SNAPSHOT OFF;
GO
ALTER DATABASE texasrangerswillwinitthisyear SET MULTI_USER;
GO

-- Reset AccountId 1 to a known starting balance for clean demo
UPDATE dbo.Accounts SET Balance = 100.00 WHERE AccountId = 1;
GO

-- ============================================================================
-- STEP 1: Confirm everything is OFF (lock-based READ COMMITTED, no versioning)
-- ============================================================================
SELECT name, 
    is_read_committed_snapshot_on AS RCSI,
    is_accelerated_database_recovery_on AS ADR,
    is_optimized_locking_on AS OL
FROM sys.databases WHERE name = N'texasrangerswillwinitthisyear';
-- Should show RCSI = 0, ADR = 0, OL = 0
GO

-- ============================================================================
-- STEP 2: Show the blocking problem
-- ============================================================================

-- Show the current balance so the audience has a reference point:
SELECT AccountId, AccountName, Balance FROM dbo.Accounts WHERE AccountId = 1;
-- ^^^ Note this value — the audience needs to recognize it later.

-- Start a transaction and hold the X lock:
BEGIN TRAN;
    UPDATE dbo.Accounts
    SET Balance = Balance + 100.00,
        LastUpdated = SYSUTCDATETIME()
    WHERE AccountId = 1;
    -- DO NOT COMMIT — hold the X lock
    -- Point out: "Session 1 holds an exclusive lock on AccountId = 1"

-- Show the lock:
SELECT resource_type, resource_description, request_mode, request_status
FROM sys.dm_tran_locks
WHERE request_session_id = @@SPID AND resource_type IN (N'KEY', N'RID', N'PAGE');
GO

-- >>> Go to Session 2: run the SELECT — it will BLOCK

-- While Session 2 is blocked, show the blocking:
SELECT
    blocking.session_id AS BlockingSession,
    waiting.session_id  AS WaitingSession,
    waiting.wait_type,
    waiting.wait_time,
    waiting.last_wait_type
FROM sys.dm_exec_sessions blocking
INNER JOIN sys.dm_exec_requests waiting
    ON blocking.session_id = waiting.blocking_session_id;
GO

-- Commit — Session 2 immediately returns
COMMIT;
GO

-- TALKING POINT: "That's how SQL Server has worked since 1.0. Readers wait 
-- for writers. Writers wait for readers. Everyone waits."

-- ============================================================================
-- STEP 2B: The Wrong Fix — NOLOCK (dirty read proof)
-- ============================================================================
-- TALKING POINT: "So what does your team do? They add NOLOCK. Let's see
-- what that actually does."

-- Start a transaction and update the row — DO NOT COMMIT
BEGIN TRAN;
    UPDATE dbo.Accounts
    SET Balance = Balance + 999999.00,
        LastUpdated = SYSUTCDATETIME()
    WHERE AccountId = 1;
    -- The balance is now inflated by ~$1M. But we haven't committed.

-- >>> Go to Session 2: run the NOLOCK SELECT — it returns the dirty value!

-- Actually, never mind — roll it back
ROLLBACK;
GO

-- >>> Go to Session 2: read the real value — no $999,999

-- TALKING POINT: "NOLOCK returned data that was NEVER committed. That 
-- balance never existed. If this was a financial report, you just told
-- your CFO a customer has a million dollars they don't have.
-- 
-- That's a dirty read. And it's the LEAST bad thing NOLOCK does —
-- it can also skip rows entirely, return duplicate rows, and crash
-- mid-scan. NOLOCK is not a solution. Versioning is. Let me show you."

-- ============================================================================
-- END OF DEMO 1 — Transition to Part 2 where we enable RCSI
-- ============================================================================
