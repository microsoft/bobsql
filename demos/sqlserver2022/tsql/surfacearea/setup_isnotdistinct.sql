USE [WideWorldImporters];
GO
DROP INDEX Sales.Orders.pickingdateidx;
GO
CREATE INDEX pickingdateidx ON Sales.Orders (PickingCompletedWhen);
GO