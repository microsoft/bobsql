-- Category report: dashboard aggregation across all categories
-- Full scan — blocked by any writer holding X locks
SET NOCOUNT ON;
SELECT CategoryId,
       COUNT(*) AS ProductCount,
       SUM(QuantityOnHand) AS TotalStock,
       SUM(CASE WHEN QuantityOnHand <= ReorderPoint THEN 1 ELSE 0 END) AS NeedsReorder,
       AVG(UnitPrice) AS AvgPrice
FROM dbo.Products
GROUP BY CategoryId
ORDER BY CategoryId;
