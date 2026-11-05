USE [WideWorldImporters];
GO
IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 's3_wwi')
	DROP EXTERNAL DATA SOURCE s3_wwi;
GO
CREATE EXTERNAL DATA SOURCE s3_wwi
WITH
(
 LOCATION = 's3://<your local IP>:9000'
,CREDENTIAL = s3_wwi_cred
);
GO