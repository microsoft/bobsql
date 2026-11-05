USE WideWorldImporters;
GO
SET STATISTICS TIME ON;
GO
-- The best plan for this parameter is an index seek
EXEC Warehouse.GetStockItemsbySupplier 2;
GO