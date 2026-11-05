USE [AdventureWorks];
GO
IF NOT EXISTS(SELECT * FROM sys.symmetric_keys WHERE [name] = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'<pwd>';
END;
GO
IF EXISTS(SELECT * FROM sys.[database_scoped_credentials] WHERE NAME = '<azure ai URL>')
BEGIN
	DROP DATABASE SCOPED CREDENTIAL [<azure ai URL>]
END
CREATE DATABASE SCOPED CREDENTIAL [<azure ai URL>]
WITH IDENTITY = 'HTTPEndpointHeaders', SECRET = '{"api-key": "<api_key>"}';
GO;


