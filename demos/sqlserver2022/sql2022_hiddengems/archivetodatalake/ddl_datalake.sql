USE SalesDB;
GO
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongPass0wrd!';
GO
DROP EXTERNAL DATA SOURCE bwdatalake;
GO
DROP DATABASE SCOPED CREDENTIAL bwdatalake_creds;
GO
CREATE DATABASE SCOPED CREDENTIAL bwdatalake_creds   
WITH IDENTITY = 'SHARED ACCESS SIGNATURE', 
SECRET = '<SAS Token>';
GO
CREATE EXTERNAL DATA SOURCE bwdatalake
WITH
(
 LOCATION = 'abs://bwdatalake@bwdatalakestorage.blob.core.windows.net'
,CREDENTIAL = bwdatalake_creds
);
GO
IF EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'ParquetFileFormat')
	DROP EXTERNAL FILE FORMAT ParquetFileFormat;
CREATE EXTERNAL FILE FORMAT ParquetFileFormat WITH(FORMAT_TYPE = PARQUET);
GO