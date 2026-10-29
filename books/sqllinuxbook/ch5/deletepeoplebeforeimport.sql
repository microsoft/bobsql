USE [WideWorldImporters]
GO
ALTER TABLE [Sales].[Customers] NOCHECK CONSTRAINT ALL
GO
ALTER TABLE [Application].[People] NOCHECK CONSTRAINT ALL
GO
DELETE FROM [Application].[People]
GO