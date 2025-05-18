USE master;
GO
DROP DATABASE IF EXISTS orders;
GO
CREATE DATABASE orders;
GO
USE orders;
GO
DROP TABLE IF EXISTS dbo.Orders;
GO
CREATE TABLE dbo.Orders(
order_id int NOT NULL IDENTITY,
order_info json NOT NULL
);
GO

-- INSERT JSON documents directly into the JSON type
INSERT INTO dbo.Orders (order_info)
VALUES
(
'{
"OrderNumber": "S043659",
"Date": "2024-05-24T08:01:00",
"AccountNumber": "AW29825",
"Price": 59.99,
"Quantity": 1
}'
),
(
'{
"OrderNumber": "S043661",
"Date": "2024-05-20T12:20:00",
"AccountNumber": "AW7365",
"Price": 24.99,
"Quantity": 3
}'
)

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

-- Product a set of key/value pairs
SELECT JSON_OBJECTAGG(o.order_id:o.order_info)
FROM dbo.Orders o;
GO

-- Modify a value inline
SELECT o.order_id, JSON_VALUE(o.order_info, '$.Quantity') AS Quantity
FROM dbo.Orders o;
GO
UPDATE dbo.Orders
   SET order_info.modify('$.Quantity', 2)
WHERE order_id = 1;
GO
SELECT o.order_id, JSON_VALUE(o.order_info, '$.Quantity') AS Quantity
FROM dbo.Orders o;
GO






















