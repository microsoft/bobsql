USE [AdventureWorks];
GO
IF NOT EXISTS(SELECT * FROM sys.symmetric_keys WHERE [name] = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'<strongpassword>';
END;
GO
IF EXISTS(SELECT * FROM sys.[database_scoped_credentials] WHERE NAME = 'https://<azureai>.openai.azure.com')
BEGIN
	DROP DATABASE SCOPED CREDENTIAL [https://<azureai>.openai.azure.com];
END;
CREATE DATABASE SCOPED CREDENTIAL [https://<azureai>.openai.azure.com]
WITH IDENTITY = 'HTTPEndpointHeaders', SECRET = '{"api-key": "<api_key>"}';
GO

