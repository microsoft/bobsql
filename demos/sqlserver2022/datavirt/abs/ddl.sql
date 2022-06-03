USE AdventureWorks;
GO
DROP MASTER KEY;
GO
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'S0me!nfo';
GO
DROP DATABASE SCOPED CREDENTIAL AzureStorageCredential;
GO
-- IDENTITY: any string (this is not used for authentication to Azure storage).  
-- SECRET: your Azure storage account key. 
CREATE DATABASE SCOPED CREDENTIAL AzureStorageCredential
WITH IDENTITY = 'user', 
SECRET = 'JlRLgPTjPwbjG+LDi99O5JwA9tGOu8rsMPlOu4Jz+usckuA1urbjNdiJao3+8O1CS9ltLoism4zn+AStUJ313g==';
GO
DROP EXTERNAL DATA SOURCE MyAzureStorage;
GO
CREATE EXTERNAL DATA SOURCE MyAzureStorage
WITH
  ( LOCATION = 'abs://customerdata@bwazureblob.blob.core.windows.net',
    CREDENTIAL = AzureStorageCredential
  );
GO
CREATE EXTERNAL FILE FORMAT ParquetFileFormat WITH(FORMAT_TYPE = PARQUET);
GO
DROP EXTERNAL TABLE [dbo].[Customer];
GO
CREATE EXTERNAL TABLE [dbo].[Customer] (  
      [SensorKey] int NOT NULL,
      [CustomerKey] int NOT NULL,
      [GeographyKey] int NULL,
      [Speed] float NOT NULL,
      [YearMeasured] int NOT NULL  
)  
WITH (LOCATION='/',
      DATA_SOURCE = MyAzureStorage,  
      FILE_FORMAT = ParquetFileFormat  
);
SELECT * FROM [dbo].[Customer];
GO