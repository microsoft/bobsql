-- This is a demo for the enhanced IS [NOT] DISTINCT FROM T-SQL function in SQL Server 2022
-- Credits to Itzik Ben-Gan for providing a base for these demos
USE [WideWorldImporters];
GO
SELECT * FROM Sales.Orders WHERE
PickingCompletedWhen = '2013-01-01 12:00:00.0000000';
GO
SELECT * FROM Sales.Orders WHERE
PickingCompletedWhen = NULL;
GO
DECLARE @dt AS DATE = NULL;
SELECT * FROM Sales.Orders 
WHERE ISNULL(PickingCompletedWhen, '99991231') = ISNULL(@dt, '99991231');
GO
DECLARE @dt AS DATE = NULL;
SELECT *
FROM Sales.Orders
WHERE PickingCompletedWhen IS NOT DISTINCT FROM @dt;
GO