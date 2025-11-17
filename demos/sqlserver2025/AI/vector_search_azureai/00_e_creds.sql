USE [AdventureWorks];
GO
IF NOT EXISTS(SELECT * FROM sys.symmetric_keys WHERE [name] = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'$StrongPassw0rd';
END;
GO
IF EXISTS(SELECT * FROM sys.[database_scoped_credentials] WHERE NAME = 'https://productsopenai.openai.azure.com')
BEGIN
	DROP DATABASE SCOPED CREDENTIAL [https://productsopenai.openai.azure.com]
END
CREATE DATABASE SCOPED CREDENTIAL [https://productsopenai.openai.azure.com]
WITH IDENTITY = 'HTTPEndpointHeaders', SECRET = '{"api-key": "G0kOcAVo0E0p1aRjcjAdbGpOv71wkxwaWYXmFWF2d9ESRwHpOYOAJQQJ99BIACYeBjFXJ3w3AAABACOGrjwu"}';
GO


