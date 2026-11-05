-- ============================================================================
-- DEMO 2e — SESSION 2 (right window): The unrelated modifier
-- FK Scan Conflict Trap
--
-- Load this in SSMS Session 2 (right window).
-- Load demo2e-fk-scan-conflict-session1.sql in Session 1 (left window).
-- ============================================================================
USE texasrangerswillwinitthisyear;
GO

-- >>> Session 1 has opened a SNAPSHOT transaction.
-- Modify an unrelated OrderItem:
UPDATE dbo.OrderItems SET Quantity = Quantity + 1 WHERE ItemId = 1;
GO

-- >>> Go back to Session 1: DELETE an Order — 3960 because FK scan hits this row!
