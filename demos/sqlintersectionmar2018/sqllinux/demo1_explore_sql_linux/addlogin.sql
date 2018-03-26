USE [master]
GO

IF EXISTS (select * from sys.server_principals where name = 'sqllinux')
DROP LOGIN [sqllinux]
GO

CREATE LOGIN [sqllinux] WITH PASSWORD=N'Sql2017isfast', DEFAULT_DATABASE=[master], DEFAULT_LANGUAGE=[us_english], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF
GO

ALTER SERVER ROLE [sysadmin] ADD MEMBER [sqllinux]
GO
