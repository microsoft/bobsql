-- ============================================================================
-- DEMO 1 — SESSION 2 (right window): The Reader
-- Part 1: Why Versioning?
--
-- Load this in SSMS Session 2 (right window).
-- Load demo1-blocking-session1.sql in Session 1 (left window).
-- ============================================================================
USE texasrangerswillwinitthisyear;
GO

-- ============================================================================
-- STEP 2: Blocking proof
-- ============================================================================

-- >>> Session 1 has started a transaction and holds an X lock.
-- Run this SELECT — it will BLOCK:
SELECT AccountId, AccountName, Balance
FROM dbo.Accounts
WHERE AccountId = 1;
-- ^^^ This hangs. Let it hang for 3-5 seconds so the audience feels it.
GO

-- >>> Go back to Session 1: show the blocking DMV, then COMMIT.
-- Session 2 immediately returns after Session 1 commits.

-- ============================================================================
-- STEP 2B: The Wrong Fix — NOLOCK (dirty read proof)
-- ============================================================================

-- >>> Session 1 has started a new transaction with a $999,999 update.
-- Read with NOLOCK — returns instantly!
SELECT AccountId, AccountName, Balance
FROM dbo.Accounts WITH (NOLOCK)
WHERE AccountId = 1;
-- ^^^ Returns immediately. The audience sees a balance inflated by $999,999.
-- "Look, no blocking! Problem solved, right?"
GO

-- >>> Go back to Session 1: ROLLBACK (the change never happened).

-- Now read the actual committed value:
SELECT AccountId, AccountName, Balance
FROM dbo.Accounts
WHERE AccountId = 1;
-- ^^^ The real balance — no $999,999. That money never existed.
GO
