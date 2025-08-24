USE orders;
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






















