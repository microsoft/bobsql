USE [WideWorldImporters]
GO
DROP INDEX IF EXISTS Sales.Orders.NCL_Orders_Date
GO
CREATE NONCLUSTERED INDEX NCL_Orders_Date ON Sales.Orders (OrderDate) INCLUDE (CustomerID)
GO