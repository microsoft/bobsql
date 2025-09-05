USE orders;
GO

-- Find a specific JSON value
SELECT o.order_id, JSON_VALUE(o.order_info, '$.AccountNumber') AS
account_number
FROM dbo.Orders o;
GO

-- Dump out all JSON values
SELECT o.order_info
FROM dbo.Orders o;
GO

-- Produce an array of JSON values from all rows in the table
SELECT JSON_ARRAYAGG(o.order_info)
FROM dbo.Orders o;
GO

-- Produce a set of key/value pairs
SELECT JSON_OBJECTAGG(o.order_id:o.order_info)
FROM dbo.Orders o;
GO


















