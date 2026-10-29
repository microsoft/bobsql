USE [MASTER]
GO
USE master
GO
IF EXISTS (select * from sys.server_principals where name = 'newuser')
    DROP LOGIN [newuser]
GO
CREATE LOGIN [newuser] WITH PASSWORD=N'<REDACTED>', DEFAULT_DATABASE=[SecureMyDatabase]
GO