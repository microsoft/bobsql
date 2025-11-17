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
-- JSON now validated on INSERT
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