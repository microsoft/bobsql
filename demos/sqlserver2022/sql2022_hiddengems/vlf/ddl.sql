USE [master]
GO
DROP DATABASE IF EXISTS testvlf;
GO
CREATE DATABASE testvlf
 ON  PRIMARY 
( NAME = N'testvlf', FILENAME = N'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\testvlf.mdf' , SIZE = 2GB , MAXSIZE = UNLIMITED, FILEGROWTH = 65536KB)
 LOG ON 
( NAME = N'testvlf_log', FILENAME = N'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\testvlf_log.ldf' , SIZE = 8MB , MAXSIZE = 2048GB , FILEGROWTH = 65536KB);
GO
USE testvlf;
GO
DROP TABLE IF EXISTS growtable;
GO
CREATE TABLE growtable (COL1 int, COL2 char(7000) not null);
GO
SET NOCOUNT ON;
GO
BEGIN TRAN
GO
DECLARE @x INT;
SET @x = 0;
WHILE (@x < 150000)
BEGIN
	INSERT INTO growtable VALUES (@x, 'x');
	SET @x = @x + 1
END
GO
SET NOCOUNT OFF;
GO
COMMIT TRAN
GO