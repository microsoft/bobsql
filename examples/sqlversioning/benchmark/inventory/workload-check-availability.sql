-- Check availability: website checks stock for a category
-- Readers need S locks — blocked by warehouse restock X locks in baseline
SET NOCOUNT ON;
DECLARE @CategoryId INT = ABS(CHECKSUM(NEWID())) % 20;
SELECT ProductId, ProductName, QuantityOnHand, UnitPrice
FROM dbo.Products
WHERE CategoryId = @CategoryId
  AND QuantityOnHand > 0
ORDER BY ProductName;
