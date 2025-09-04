USE [AdventureWorks];
GO
IF NOT EXISTS(SELECT * FROM sys.symmetric_keys WHERE [name] = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'V3RYStr0NGP@ssw0rd!';
END;
GO
IF EXISTS(SELECT * FROM sys.[database_scoped_credentials] WHERE NAME = 'https://productsopenai.openai.azure.com')
BEGIN
	DROP DATABASE SCOPED CREDENTIAL [https://productsopenai.openai.azure.com];
END;
CREATE DATABASE SCOPED CREDENTIAL [https://productsopenai.openai.azure.com]
WITH IDENTITY = 'HTTPEndpointHeaders', SECRET = '{"api-key": "bef26b08e68e4e18a79929007a47c8ec"}';
GO

