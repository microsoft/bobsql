USE WideWorldImporters;
GO
-- The best plan for this parameter is an index seek
SET STATISTICS TIME ON;
GO
USE WideWorldImporters;
GO
EXEC Warehouse.GetStockItemsbySupplier 2
GO