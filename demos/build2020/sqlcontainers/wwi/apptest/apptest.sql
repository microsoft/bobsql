USE [WideWorldImporters]
GO 
SELECT @@VERSION
GO
PRINT 'How many objects are in the database'
GO
SELECT COUNT(*) AS numobjects FROM sys.objects
GO