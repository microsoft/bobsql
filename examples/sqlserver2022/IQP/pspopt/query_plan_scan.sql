USE WideWorldImporters;
GO
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
-- The best plan for this parameter is an index scan
EXEC Warehouse.GetStockItemsbySupplier 4;
GO
