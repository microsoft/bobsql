USE WideWorldImporters;
GO
-- Add StockItems to cause a data skew in Suppliers
DECLARE @StockItemID int = 228;--starting item id
DECLARE @SupplierID int = 4;
DECLARE @BatchSize int = 50000; --insert in batches of this size
DECLARE @MaxStockItemID int = 20000000;--size of the skew

SET NOCOUNT ON;
DELETE FROM Warehouse.StockItems WHERE StockItemID >= @StockItemID;

WHILE (@StockItemID <= @MaxStockItemID)
BEGIN
	BEGIN TRANSACTION
	
	INSERT INTO Warehouse.StockItems
	(
		StockItemID, StockItemName, SupplierID, UnitPackageID, OuterPackageID, LeadTimeDays, 
		QuantityPerOuter, IsChillerStock, TaxRate, UnitPrice, TypicalWeightPerUnit, LastEditedBy
	)
	SELECT [value], 'Dallas Cowboys Shirt' + CONVERT(varchar(10), [value]), @SupplierID, 10, 9, 12, 100, 0, 15.00, 100.00, 0.300, 1
	FROM GENERATE_SERIES(START = @StockItemID, STOP = (@StockItemID + @BatchSize - 1));
	
	COMMIT TRANSACTION
	
	SET @StockItemID += @BatchSize;
END

SET NOCOUNT OFF
GO