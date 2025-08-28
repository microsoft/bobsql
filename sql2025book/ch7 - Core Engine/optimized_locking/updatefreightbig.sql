USE AdventureWorks;
GO
-- Run this batch first to update 10000 rows
DECLARE @minsalesorderid INT;
SELECT @minsalesorderid = MIN(SalesOrderID) FROM Sales.SalesOrderHeader;
BEGIN TRAN
UPDATE Sales.SalesOrderHeader
SET Freight = Freight * .10
WHERE SalesOrderID <= @minsalesorderid + 10000;
GO

-- Rollback the transaction when needed
ROLLBACK TRAN;
GO
