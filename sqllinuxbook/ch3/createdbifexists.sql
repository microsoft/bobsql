USE master
GO
IF NOT EXISTS (
   SELECT name
   FROM sys.databases
   WHERE name = N'WideWorldImporters'
)
CREATE DATABASE [WideWorldImporters]
GO