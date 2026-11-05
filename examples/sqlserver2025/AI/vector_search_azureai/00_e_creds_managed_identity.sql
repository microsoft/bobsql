USE [master];
GO

EXECUTE sp_configure 'allow server scoped db credentials', 1;
RECONFIGURE WITH OVERRIDE;
GO

USE [AdventureWorks];
GO

IF NOT EXISTS(SELECT * FROM sys.symmetric_keys WHERE [name] = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'<pwd>';
END;
GO

IF EXISTS(SELECT * FROM sys.[database_scoped_credentials] WHERE [name] = 'https://<your-azure-openai-resource>.openai.azure.com/')
BEGIN
    DROP DATABASE SCOPED CREDENTIAL [https://<your-azure-openai-resource>.openai.azure.com/];
END;
GO

CREATE DATABASE SCOPED CREDENTIAL [https://<your-azure-openai-resource>.openai.azure.com/]
WITH IDENTITY = 'Managed Identity',
     SECRET = '{"resourceid":"https://cognitiveservices.azure.com"}';
GO