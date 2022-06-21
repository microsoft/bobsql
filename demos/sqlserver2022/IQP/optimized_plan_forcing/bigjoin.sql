USE WideWorldImporters;
GO
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
SET STATISTICS TIME ON
GO
SELECT o.OrderID, ol.OrderLineID, c.CustomerName, cc.CustomerCategoryName, p.FullName, city.CityName, sp.StateProvinceName, country.CountryName, si.StockItemName
FROM Sales.Orders o
JOIN Sales.Customers c
ON o.CustomerID = c.CustomerID
JOIN Sales.CustomerCategories cc
ON c.CustomerCategoryID = cc.CustomerCategoryID
JOIN Application.People p
ON o.ContactPersonID = p.PersonID
JOIN Application.Cities city
ON city.CityID = c.DeliveryCityID
JOIN Application.StateProvinces sp
ON city.StateProvinceID = sp.StateProvinceID
JOIN Application.Countries country
ON sp.CountryID = country.CountryID
JOIN Sales.OrderLines ol
ON ol.OrderID = o.OrderID
JOIN Warehouse.StockItems si
ON ol.StockItemID = si.StockItemID
UNION ALL
SELECT o.OrderID, ol.OrderLineID, c.CustomerName, cc.CustomerCategoryName, p.FullName, city.CityName, sp.StateProvinceName, country.CountryName, si.StockItemName
FROM Sales.Orders o
JOIN Sales.Customers c
ON o.CustomerID = c.CustomerID
JOIN Sales.CustomerCategories cc
ON c.CustomerCategoryID = cc.CustomerCategoryID
JOIN Application.People p
ON o.ContactPersonID = p.PersonID
JOIN Application.Cities city
ON city.CityID = c.DeliveryCityID
JOIN Application.StateProvinces sp
ON city.StateProvinceID = sp.StateProvinceID
JOIN Application.Countries country
ON sp.CountryID = country.CountryID
JOIN Sales.OrderLines ol
ON ol.OrderID = o.OrderID
JOIN Warehouse.StockItems si
ON ol.StockItemID = si.StockItemID
WHERE o.OrderID NOT IN (2,4,6,8,10,11,12,17,18,19,23,25,27,30,31,32,33,34,35,36,37,38,39,40,41,42,43)
ORDER BY OrderID
GO