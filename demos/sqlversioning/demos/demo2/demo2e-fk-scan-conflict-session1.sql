-- ============================================================================
-- DEMO 2e — SESSION 1 (left window): FK Scan Conflict Trap
-- Error 3960 triggered by FK validation on rows you didn't touch
--
-- Load this in SSMS Session 1 (left window).
-- Load demo2e-fk-scan-conflict-session2.sql in Session 2 (right window).
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

-- TALKING POINT: "Now here's the trap. Error 3960 triggered by FK
-- validation — on rows you didn't even touch."

-- Confirm: OrderItems has NO index on OrderId (intentional from setup)
SELECT 
    i.name AS IndexName, 
    c.name AS ColumnName
FROM sys.indexes i
JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE i.object_id = OBJECT_ID(N'dbo.OrderItems');
GO
-- Should show only PK_OrderItems on ItemId — no index on OrderId

-- Start a Snapshot transaction
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRAN;
    SELECT TOP 1 OrderId FROM dbo.Orders;
GO

-- >>> Go to Session 2: modify an unrelated OrderItem.

-- Delete an Order — FK scan hits the modified row → 3960:
DELETE FROM dbo.Orders WHERE OrderId = 1;
-- ^^^ ERROR 3960 — conflict on OrderItems, not on the row we're deleting!
GO

-- TALKING POINT: "The conflict wasn't on the row we deleted. It was on an
-- unrelated OrderItems row that another session modified. Without an index
-- on the FK column, SQL Server does a full scan and hits the modified row."

ROLLBACK;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

-- ============================================================================
-- The fix: add the FK index
-- ============================================================================
CREATE NONCLUSTERED INDEX IX_OrderItems_OrderId ON dbo.OrderItems(OrderId);
GO

-- TALKING POINT: "Add the index, and the engine seeks instead of scans.
-- No more phantom conflicts. Always index your FK columns."
