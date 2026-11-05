USE [WideWorldImporters];
GO
SELECT c.CustomerName, SUM(wct.OutstandingBalance) as total_balance
FROM wwi_customer_transactions wct
JOIN Sales.Customers c
ON wct.CustomerID = c.CustomerID
GROUP BY c.CustomerName
ORDER BY total_balance DESC;
GO