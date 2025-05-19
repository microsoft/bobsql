USE [AdventureWorks];
GO
IF NOT EXISTS(SELECT * FROM sys.symmetric_keys WHERE [name] = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'<pwd>';
END;
GO
IF EXISTS(SELECT * FROM sys.[database_scoped_credentials] WHERE NAME = 'https://<azureai>')
BEGIN
	DROP DATABASE SCOPED CREDENTIAL [https://<azureai>]
CREATE DATABASE SCOPED CREDENTIAL [https://<azureai]
WITH IDENTITY = 'HTTPEndpointHeaders', SECRET = '{"api-key": "<apikey>"}';
GO

