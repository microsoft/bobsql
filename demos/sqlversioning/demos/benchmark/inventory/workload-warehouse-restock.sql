-- Warehouse restock: UPDATE ~200 rows in a random category
-- Simulates app holding transaction open during processing (validation, API call, etc.)
-- X locks held for ~50ms in baseline → blocks readers on same category
-- Under RCSI: readers use version store, unaffected by held X locks
SET NOCOUNT ON;
DECLARE @CategoryId INT = ABS(CHECKSUM(NEWID())) % 20;
DECLARE @Qty INT = ABS(CHECKSUM(NEWID())) % 50 + 10;
BEGIN TRAN
UPDATE TOP(200) dbo.Products
SET QuantityOnHand = QuantityOnHand + @Qty,
    LastRestocked = SYSUTCDATETIME()
WHERE CategoryId = @CategoryId;
WAITFOR DELAY '00:00:00.050';
COMMIT
