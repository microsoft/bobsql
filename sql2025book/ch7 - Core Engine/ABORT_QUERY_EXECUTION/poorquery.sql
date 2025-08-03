USE [AdventureWorks];
GO
WITH LargeDataSet AS (
    SELECT 
        p.ProductID, p.Name, p.ProductNumber, p.Color, 
        s.SalesOrderID, s.OrderQty, s.UnitPrice, s.LineTotal, 
        c.CustomerID, c.AccountNumber,
        (SELECT AVG(UnitPrice) FROM Sales.SalesOrderDetail WHERE ProductID = p.ProductID) AS AvgUnitPrice,
        (SELECT COUNT(*) FROM Sales.SalesOrderDetail WHERE ProductID = p.ProductID) AS OrderCount,
        (SELECT SUM(LineTotal) FROM Sales.SalesOrderDetail WHERE ProductID = p.ProductID) AS TotalSales,
        (SELECT MAX(OrderDate) FROM Sales.SalesOrderHeader WHERE CustomerID = c.CustomerID) AS LastOrderDate,
        r.ReviewCount
    FROM 
        Production.Product p
    JOIN 
        Sales.SalesOrderDetail s ON p.ProductID = s.ProductID
    JOIN 
        Sales.SalesOrderHeader h ON s.SalesOrderID = h.SalesOrderID
    JOIN 
        Sales.Customer c ON h.CustomerID = c.CustomerID
    JOIN 
        (SELECT 
             ProductID, COUNT(*) AS ReviewCount 
         FROM 
             Production.ProductReview 
         GROUP BY 
             ProductID) r ON p.ProductID = r.ProductID
     CROSS JOIN 
       (SELECT TOP 1000 * FROM Sales.SalesOrderDetail) s2
)
SELECT 
    ld.ProductID, ld.Name, ld.ProductNumber, ld.Color, 
    ld.SalesOrderID, ld.OrderQty, ld.UnitPrice, ld.LineTotal, 
    ld.CustomerID, ld.AccountNumber, ld.AvgUnitPrice, ld.OrderCount, ld.TotalSales, ld.LastOrderDate, ld.ReviewCount
FROM 
    LargeDataSet ld
ORDER BY 
    ld.OrderQty DESC, ld.ReviewCount ASC;
GO