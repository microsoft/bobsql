-- Order lifecycle: place, ship, cancel in explicit transaction
-- INSERT + UPDATE + DELETE on wider rows with 2 NCIs
SET NOCOUNT ON;
DECLARE @CustomerId INT = (ABS(CHECKSUM(NEWID())) % 50000) + 1;
DECLARE @Amount DECIMAL(18,2) = CAST((ABS(CHECKSUM(NEWID())) % 100000) AS DECIMAL(18,2)) / 100.0;
DECLARE @Tax DECIMAL(18,2) = @Amount * 0.08;

BEGIN TRAN;
    DECLARE @NewId INT;
    INSERT INTO dbo.Orders (CustomerId, Amount, Tax, ItemDescription, ShippingAddress)
    VALUES (@CustomerId, @Amount, @Tax,
            N'Item-' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS NVARCHAR(10)),
            N'Ship to customer ' + CAST(@CustomerId AS NVARCHAR(10)));
    SET @NewId = SCOPE_IDENTITY();

    -- Mark as shipped (touches OrderStatus NCI key + ShipDate)
    UPDATE dbo.Orders
    SET OrderStatus = 2, ShipDate = SYSUTCDATETIME()
    WHERE OrderId = @NewId AND CustomerId = @CustomerId;

    -- Cancel and remove
    DELETE FROM dbo.Orders WHERE OrderId = @NewId AND CustomerId = @CustomerId;
COMMIT;
