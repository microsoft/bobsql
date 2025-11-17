USE [AdventureWorks];
GO
IF NOT EXISTS(SELECT * FROM sys.symmetric_keys WHERE [name] = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'<pwd>';
END;
GO
IF EXISTS(SELECT * FROM sys.[database_scoped_credentials] WHERE NAME = '<azure ai URL>')
BEGIN
<<<<<<< HEAD:demos/sqlserver2025/AI/vector_search_azureai/00_e_creds.sql
	DROP DATABASE SCOPED CREDENTIAL [<azure ai URL>]
END
CREATE DATABASE SCOPED CREDENTIAL [<azure ai URL>]
WITH IDENTITY = 'HTTPEndpointHeaders', SECRET = '{"api-key": "<api_key>"}';
=======
	DROP DATABASE SCOPED CREDENTIAL [https://<azureai>]
END;
GO
CREATE DATABASE SCOPED CREDENTIAL [https://<azureai]
WITH IDENTITY = 'HTTPEndpointHeaders', SECRET = '{"api-key": "<apikey>"}';
>>>>>>> 05592905700a642d79f58d7d363432a08f0b6b48:demos/sqlserver2025/AI/azureopenai/creds.sql
GO


