USE WideWorldImporters;
GO
-- Add StockItems to cause a data skew in Suppliers
--
DECLARE @StockItemID int;
DECLARE @StockItemName varchar(100);
DECLARE @SupplierID int;
SELECT @StockItemID = 228;
SET @StockItemName = 'Dallas Cowboys Shirt'+convert(varchar(10), @StockItemID);
SET @SupplierID = 4;
DELETE FROM Warehouse.StockItems WHERE StockItemID >= @StockItemID;
SET NOCOUNT ON;
BEGIN TRANSACTION;
WHILE @StockItemID <= 4000000
BEGIN
INSERT INTO Warehouse.StockItems
(StockItemID, StockItemName, SupplierID, UnitPackageID, OuterPackageID, LeadTimeDays,
QuantityPerOuter, IsChillerStock, TaxRate, UnitPrice, TypicalWeightPerUnit, LastEditedBy
)
VALUES (@StockItemID, @StockItemName, @SupplierID, 10, 9, 12, 100, 0, 15.00, 100.00, 0.300, 1);
SET @StockItemID = @StockItemID + 1;
SET @StockItemName = 'Dallas Cowboys Shirt'+convert(varchar(10), @StockItemID);
END;
COMMIT TRANSACTION;
SET NOCOUNT OFF;
GO
DECLARE @StockItemID int;
DECLARE @StockItemName varchar(100);
DECLARE @SupplierID int;
SELECT @StockItemID = 4000001;
SET @StockItemName = 'Dallas Cowboys Mug'+convert(varchar(10), @StockItemID);
SET @SupplierID = 5;
DELETE FROM Warehouse.StockItems WHERE StockItemID >= @StockItemID;
SET NOCOUNT ON;
BEGIN TRANSACTION;
WHILE @StockItemID <= 8000000
BEGIN
INSERT INTO Warehouse.StockItems
(StockItemID, StockItemName, SupplierID, UnitPackageID, OuterPackageID, LeadTimeDays,
QuantityPerOuter, IsChillerStock, TaxRate, UnitPrice, TypicalWeightPerUnit, LastEditedBy
)
VALUES (@StockItemID, @StockItemName, @SupplierID, 10, 9, 12, 100, 0, 15.00, 100.00, 0.300, 1);
SET @StockItemID = @StockItemID + 1;
SET @StockItemName = 'Dallas Cowboys Mug'+convert(varchar(10), @StockItemID);
END;
COMMIT TRANSACTION;
SET NOCOUNT OFF;
GO