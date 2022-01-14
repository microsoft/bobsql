-- The best plan for this parameter is an index seek
USE WideWorldImporters;
GO
EXEC Warehouse.GetStockItemsbySupplier 2
GO