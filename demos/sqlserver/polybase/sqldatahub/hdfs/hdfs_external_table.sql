USE [master]
GO
-- Enabled PB connectivity to a Hadoop HDFS source which in this case is just Azure Blob Storage
--
sp_configure @configname = 'hadoop connectivity', @configvalue = 7;
GO
RECONFIGURE
GO
-- STOP: SQL Server must be restarted for this to take effect
--
USE [WideWorldImporters]
GO
-- Only run this if you have not already created a master key in the db
--
--CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'S0me!nfo'
--GO
-- IDENTITY: any string (this is not used for authentication to Azure storage).  
-- SECRET: your Azure storage account key.  
DROP DATABASE SCOPED CREDENTIAL AzureStorageCredential
GO
CREATE DATABASE SCOPED CREDENTIAL AzureStorageCredential
WITH IDENTITY = 'user', Secret = 'C5aFpK587sIDFIMSEqXwA08xlhDM34/rfOz2g+sVq/hcKReo6agvT9JZcWGe9NtEyHEypK095WZtDdE/gkKZNQ=='
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
-- LOCATION: path to file or directory that contains the data (relative to HDFS root).
DROP EXTERNAL TABLE [WWI_Order_Reviews]
GO
CREATE EXTERNAL TABLE [dbo].[WWI_Order_Reviews] (  
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
CREATE STATISTICS StatsforReviews on WWI_Order_Reviews(OrderID, CustomerID)
GO