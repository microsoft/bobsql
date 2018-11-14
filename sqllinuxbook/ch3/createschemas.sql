USE [WideWorldImporters]
GO
IF EXISTS (select * from sys.schemas where name = 'Application')
    DROP SCHEMA [Application]
GO
CREATE SCHEMA [Application]
GO
IF EXISTS (select * from sys.schemas where name = 'Sales')
    DROP SCHEMA [Sales]
GO
CREATE SCHEMA [Sales]
GO
IF EXISTS (select * from sys.schemas where name = 'Sequences')
    DROP SCHEMA [Sequences]
GO
CREATE SCHEMA [Sequences]
GO