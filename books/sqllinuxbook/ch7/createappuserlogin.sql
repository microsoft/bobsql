USE [MASTER]
GO
USE master
GO
IF EXISTS (select * from sys.server_principals where name = 'appuser')
    DROP LOGIN [appuser]
GO
CREATE LOGIN [appuser] WITH PASSWORD=N'<REDACTED>', DEFAULT_DATABASE=[WideWorldImporters]
GO
