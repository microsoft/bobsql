-- Order fulfillment: UPDATE single product (decrement stock)
SET NOCOUNT ON;
DECLARE @ProductId INT = (ABS(CHECKSUM(NEWID())) % 200000) + 1;
UPDATE dbo.Products
SET QuantityOnHand = QuantityOnHand - 1
WHERE ProductId = @ProductId
  AND QuantityOnHand > 0;
