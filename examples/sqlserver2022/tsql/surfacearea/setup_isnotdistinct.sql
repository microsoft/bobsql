USE [WideWorldImporters];
GO
DROP INDEX IF EXISTS Sales.Orders.pickingdateidx;
GO
CREATE INDEX pickingdateidx ON Sales.Orders (PickingCompletedWhen);
GO