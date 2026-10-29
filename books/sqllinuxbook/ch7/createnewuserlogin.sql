USE [MASTER]
GO
USE master
GO
IF EXISTS (select * from sys.server_principals where name = 'newuser')
    DROP LOGIN [newuser]
GO
CREATE LOGIN [newuser] WITH PASSWORD=N'Sql2017isfast', DEFAULT_DATABASE=[SecureMyDatabase]
GO