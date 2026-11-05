-- This is a demo for the enhanced IS [NOT] DISTINCT FROM T-SQL function in SQL Server 2022
-- Credits to Itzik Ben-Gan for providing a base for these demos
-- Enable Include Actual Execution Plan for each query
-- Step 1: Query for a specific value which should yield 35 rows using an Index Seek for pickingdateidx
USE [WideWorldImporters];
GO
DECLARE @dt datetime2 = '2013-01-01 12:00:00.0000000'
SELECT * FROM Sales.Orders WHERE
PickingCompletedWhen = @dt;
GO
-- Step 2: Find all the orders where picking was not completed. This shows 0 rows even though there is ~ 3000 rows with a NULL value
USE [WideWorldImporters];
GO
DECLARE @dt datetime2 = NULL
SELECT * FROM Sales.Orders WHERE
PickingCompletedWhen = @dt;
GO
-- Step 3: Try to use ISNULL. Works but requires a scan
USE [WideWorldImporters];
GO
DECLARE @dt AS DATE = NULL;
SELECT * FROM Sales.Orders 
WHERE ISNULL(PickingCompletedWhen, '99991231') = ISNULL(@dt, '99991231');
GO
-- Step 4: Try to use the new operator. Should yield ~3000 rows but use an index seek
USE [WideWorldImporters];
GO
DECLARE @dt datetime2 = NULL
SELECT *
FROM Sales.Orders
WHERE PickingCompletedWhen IS NOT DISTINCT FROM @dt;
GO