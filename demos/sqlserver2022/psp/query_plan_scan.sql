-- The best plan for this parameter is an index scan
USE WideWorldImporters;
GO
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE
GO
EXEC Warehouse.GetStockItemsbySupplier 4
GO
