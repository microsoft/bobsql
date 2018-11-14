USE [WideWorldImporters]
GO
SET STATISTICS IO ON
GO
SET STATISTICS XML ON
GO
SELECT COUNT(*) FROM [Sales].[CustomerTransactions]
WHERE TransactionDate between '2013-01-01' and '2014-01-01'
GO