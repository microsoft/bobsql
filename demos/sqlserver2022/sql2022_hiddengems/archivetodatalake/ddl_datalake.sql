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
SECRET = 'sv=2021-06-08&ss=bfqt&srt=co&sp=rwdlacupyx&se=2023-07-29T05:48:41Z&st=2023-02-16T22:48:41Z&spr=https&sig=7TMRwE9EFlN%2Fxg6RASNzq%2FfnXozMDs1THKFl5JQUZeQ%3D';
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