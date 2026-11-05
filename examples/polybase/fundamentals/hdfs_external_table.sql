-- Runtime credentials: SQLCMD variables; never save supplied values in source.
IF N'$(ExternalSecret)' = N'$' + N'(ExternalSecret)' OR LEN(N'$(ExternalSecret)') = 0
BEGIN
    RAISERROR('Supply ExternalSecret using SQLCMD mode. See SECRET-SCANNING.md. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END;
GO
IF N'$(MasterKeyPassword)' = N'$' + N'(MasterKeyPassword)' OR LEN(N'$(MasterKeyPassword)') = 0
BEGIN
    RAISERROR('Supply MasterKeyPassword using SQLCMD mode. See SECRET-SCANNING.md. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END;
GO
USE [master]
GO
-- Enabled PB connectivity to a Hadoop HDFS source which in this case is just Azure Blob Storage
--
sp_configure @configname = 'hadoop connectivity', @configvalue = 7;
GO
RECONFIGURE
GO

-- Enable PB export to be able to ingest data into the HDFS target
--
sp_configure 'allow polybase export', 1
GO
RECONFIGURE
GO

-- STOP: SQL Server must be restarted for this to take effect
--
USE [WideWorldImporters]
GO
-- Only run this if you have not already created a master key in the db
--
--CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$(MasterKeyPassword)'
--GO
-- IDENTITY: any string (this is not used for authentication to Azure storage).  
-- SECRET: your Azure storage account key.  
DROP DATABASE SCOPED CREDENTIAL AzureStorageCredential
GO
CREATE DATABASE SCOPED CREDENTIAL AzureStorageCredential
WITH IDENTITY = 'user', Secret = '$(ExternalSecret)'
GO
-- LOCATION:  Azure account storage account name and blob container name.  
-- CREDENTIAL: The database scoped credential created above.  
DROP EXTERNAL DATA SOURCE bwdatalake
GO
CREATE EXTERNAL DATA SOURCE bwdatalake with (  
      TYPE = HADOOP,
      LOCATION ='wasbs://wwi@bwdatalake.blob.core.windows.net',  
      CREDENTIAL = AzureStorageCredential  
)
GO
-- FORMAT TYPE: Type of format in Hadoop (DELIMITEDTEXT,  RCFILE, ORC, PARQUET).
CREATE EXTERNAL FILE FORMAT TextFileFormat WITH (  
      FORMAT_TYPE = DELIMITEDTEXT,
      FORMAT_OPTIONS (FIELD_TERMINATOR ='|',
            USE_TYPE_DEFAULT = TRUE))
GO
-- Create a schema called hdfs
--
DROP SCHEMA hdfs
GO
CREATE SCHEMA hdfs
GO
-- LOCATION: path to file or directory that contains the data (relative to HDFS root).
DROP EXTERNAL TABLE [hdfs].[WWI_Order_Reviews]
GO
CREATE EXTERNAL TABLE [hdfs].[WWI_Order_Reviews] (  
      [OrderID] int NOT NULL,
      [CustomerID] int NOT NULL,
      [Rating] int NULL,
      [Review_Comments] nvarchar(1000) NOT NULL
)  
WITH (LOCATION='/WWI/',
      DATA_SOURCE = bwdatalake,  
      FILE_FORMAT = TextFileFormat  
)
GO

-- Ingest some data
--
INSERT INTO [hdfs].[WWI_Order_Reviews] VALUES (1, 832, 10, 'I had a great experience with my order')
GO
CREATE STATISTICS StatsforReviews on [hdfs].[WWI_Order_Reviews](OrderID, CustomerID)
GO

-- Now query the external table
--
SELECT * FROM [hdfs].[WWI_Order_Reviews]
GO

-- Let's do a filter to enable pushdown
--
SELECT * FROM [hdfs].[WWI_Order_Reviews]
WHERE OrderID = 1
GO

-- Let's join the review with our order and customer data
--
SELECT o.OrderDate, c.CustomerName, p.FullName as SalesPerson, wor.Rating, wor.Review_Comments
FROM [Sales].[Orders] o
JOIN [hdfs].[WWI_Order_Reviews] wor
ON o.OrderID = wor.OrderID
JOIN [Application].[People] p
ON p.PersonID = o.SalespersonPersonID
JOIN [Sales].[Customers] c
ON c.CustomerID = wor.CustomerID
GO
GO
SET NOEXEC OFF;
GO
