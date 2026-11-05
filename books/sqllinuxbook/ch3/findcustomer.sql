USE [WideWorldImporters]
GO
SELECT c.[CustomerName], c.[WebsiteURL], p.[FullName] AS PrimaryContact
FROM [Sales].[Customers] AS c
JOIN [Application].[People] AS p
ON p.[PersonID] = c.[PrimaryContactPersonID]
GO