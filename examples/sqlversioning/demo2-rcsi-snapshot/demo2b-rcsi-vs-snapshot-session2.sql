-- ============================================================================
-- DEMO 2b — SESSION 2 (right window): The concurrent modifier
-- Statement-Level vs Transaction-Level consistency
--
-- Load this in SSMS Session 2 (right window).
-- Load demo2b-rcsi-vs-snapshot-session1.sql in Session 1 (left window).
-- ============================================================================
USE texasrangerswillwinitthisyear;
GO

-- ============================================================================
-- RCSI proof: Session 1 did its first read. Now change the row and COMMIT.
-- ============================================================================

-- >>> Session 1 has done its first SELECT (saw Balance = 1000).
-- Change the row:
UPDATE dbo.Accounts SET Balance = 2000.00 WHERE AccountId = 200;
GO

-- >>> Go back to Session 1: do the second SELECT — it sees 2000 (RCSI refreshes).

-- ============================================================================
-- Snapshot proof: Session 1 did its first read under SNAPSHOT.
-- Now change the row and COMMIT again.
-- ============================================================================

-- >>> Session 1 has reset Balance to 1000 and opened a SNAPSHOT transaction.
-- Change the row:
UPDATE dbo.Accounts SET Balance = 2000.00 WHERE AccountId = 200;
GO

-- >>> Go back to Session 1: do the second SELECT — it still sees 1000 (Snapshot holds).
