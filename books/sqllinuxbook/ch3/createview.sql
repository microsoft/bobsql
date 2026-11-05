USE [WideWorldImporters]
GO
DROP VIEW IF EXISTS [Sales].[CustomerContacts]
GO
CREATE VIEW [Sales].[CustomerContacts]
AS
SELECT c.[CustomerName], c.[WebsiteURL], p.[FullName] AS PrimaryContact
FROM [Sales].[Customers] AS c
JOIN [Application].[People] AS p
ON p.[PersonID] = c.[PrimaryContactPersonID]
GO
