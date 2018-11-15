-- Bob's cci example to show frag and tuple movement
--
USE master
GO
DROP DATABASE IF EXISTS gocowboyscci
GO
CREATE DATABASE [gocowboyscci]
 ON  PRIMARY 
( NAME = N'gocowboyscci', FILENAME = N'd:\data\gocowboyscci.mdf' , SIZE = 50Mb , MAXSIZE = UNLIMITED, FILEGROWTH = 65536KB )
 LOG ON 
( NAME = N'gocowboyscci_log', FILENAME = N'd:\data\gocowboyscci_log.ldf' , SIZE = 100Mb , MAXSIZE = 2048GB , FILEGROWTH = 65536KB )
GO

USE gocowboyscci
GO
-- Insert 1M rows into a base table and then create the cci index on top of it
-- Create the ncci index with and without DOP
DROP TABLE IF EXISTS howboutthemcowboys_base
GO
-- Create the base table with a unique key but colors that only have two types: 'Silver' and 'Blue'
--
CREATE TABLE howboutthemcowboys_base(col1 int identity primary key clustered, color char(20) not null, rowdate datetime)
GO
-- Insert 1M rows
--
SET NOCOUNT ON
GO
BEGIN TRAN
DECLARE @x int
SET @x = 0
WHILE (@x < 1048576)
BEGIN
	INSERT INTO howboutthemcowboys_base(color, rowdate) VALUES ('Silver', getdate())
	SET @x = @x + 1
	INSERT INTO howboutthemcowboys_base(color, rowdate) VALUES ('Blue', getdate())
	SET @x = @x + 1
END
COMMIT TRAN
GO
SET NOCOUNT OFF
GO
-- Now create the table with CCI
--
DROP TABLE IF EXISTS howboutthemcowboys
GO
-- Create the base table with a unique key but colors that only have two types: 'Silver' and 'Blue'
--
CREATE TABLE howboutthemcowboys(col1 int, 
color char(20) not null, 
rowdate datetime,
index cowboyscci clustered columnstore
)
GO
