-- Pure INSERT: wider row into Orders with 2 NCIs
SET NOCOUNT ON;
DECLARE @CustomerId INT = (ABS(CHECKSUM(NEWID())) % 50000) + 1;
DECLARE @Amount DECIMAL(18,2) = CAST((ABS(CHECKSUM(NEWID())) % 100000) AS DECIMAL(18,2)) / 100.0;

INSERT INTO dbo.Orders (CustomerId, Amount, Tax, ItemDescription, ShippingAddress)
VALUES (@CustomerId, @Amount, @Amount * 0.08,
        N'Item-' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS NVARCHAR(10)),
        N'Ship to customer ' + CAST(@CustomerId AS NVARCHAR(10)));
