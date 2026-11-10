-- ============================================================================
-- DEMO 2c — SESSION 2 (right window): The conflicting writer
-- Error 3960 — optimistic concurrency failure
--
-- Load this in SSMS Session 2 (right window).
-- Load demo2c-snapshot-conflict-session1.sql in Session 1 (left window).
-- ============================================================================
USE starswillwinthecup;
GO

-- >>> Session 1 has opened a SNAPSHOT transaction and read AccountId = 100.
-- Modify the same row and COMMIT:
UPDATE dbo.Accounts 
SET Balance = Balance + 999.00
WHERE AccountId = 100;
GO

-- >>> Go back to Session 1: reread 100, then try to UPDATE — ERROR 3960!
