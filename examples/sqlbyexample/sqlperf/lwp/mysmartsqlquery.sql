USE WideWorldImporters
GO
SELECT si.CustomerID, sil.InvoiceID, sil.LineProfit
FROM Sales.Invoices si
INNER JOIN Sales.InvoiceLines sil
ON si.InvoiceID = si.InvoiceID
OPTION (MAXDOP 1)
GO