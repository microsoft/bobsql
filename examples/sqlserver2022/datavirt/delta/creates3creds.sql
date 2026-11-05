USE [WideWorldImporters];
GO
IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 's3_wwi')
	DROP EXTERNAL DATA SOURCE s3_wwi;
IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 's3_wwi_cred')
    DROP DATABASE SCOPED CREDENTIAL s3_wwi_cred;
GO
CREATE DATABASE SCOPED CREDENTIAL s3_wwi_cred
WITH IDENTITY = 'S3 Access Key',
SECRET = '<user>:<password>';
GO