USE AdventureWorks2012;
GO

-- Without the WINDOW clause
SELECT SalesOrderID, ProductID, OrderQty
    ,SUM(OrderQty) OVER (PARTITION BY SalesOrderID ORDER BY SalesOrderID, ProductID ) AS Total
    ,AVG(OrderQty) OVER (PARTITION BY SalesOrderID ORDER BY SalesOrderID, ProductID) AS "Avg"
    ,COUNT(OrderQty) OVER (PARTITION BY SalesOrderID ORDER BY SalesOrderID, ProductID) AS "Count"
FROM Sales.SalesOrderDetail
WHERE SalesOrderID IN(43659,43664);
GO

-- With the WINDOW clause
SELECT SalesOrderID, ProductID, OrderQty
    ,SUM(OrderQty) OVER win1 AS Total
    ,AVG(OrderQty) OVER win1 AS "Avg"
    ,COUNT(OrderQty) OVER win1 AS "Count"
FROM Sales.SalesOrderDetail
WHERE SalesOrderID IN(43659,43664)
WINDOW win1 AS (PARTITION BY SalesOrderID ORDER BY SalesOrderID, ProductID );
GO

