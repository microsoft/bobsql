USE AdventureWorks;
GO
-- Update the highest salesorderid
DECLARE @maxsalesorderid INT;
SELECT @maxsalesorderid = MAX(SalesOrderID) FROM Sales.SalesOrderHeader;
BEGIN TRAN
UPDATE Sales.SalesOrderHeader
SET Freight = Freight * .10
WHERE SalesOrderID = @maxsalesorderid;
GO

-- Rollback the transaction when needed
ROLLBACK TRAN;
GO