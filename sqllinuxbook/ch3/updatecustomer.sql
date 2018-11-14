USE [WideWorldImporters]
GO
UPDATE [Sales].[Customers]
SET WebsiteURL = 'www.sqlonlinux.com'
WHERE CustomerName = 'WeLoveSQLOnLinux'
GO