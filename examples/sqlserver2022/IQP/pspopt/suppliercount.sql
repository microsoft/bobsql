USE WideWorldImporters;
GO
SELECT SupplierID, count(*) as supplier_count
FROM Warehouse.StockItems
GROUP BY SupplierID;
GO