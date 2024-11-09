USE master;
GO
DROP DATABASE IF EXISTS fullrecdb;
GO
CREATE DATABASE fullrecdb;
GO
USE fullrecdb;
GO
DROP TABLE IF EXISTS bigtab;
GO
CREATE TABLE bigtab (col1 INT, col2 char(7000) not null);
GO
DECLARE @x int;
SET @x = 0;
WHILE (@x < 10)
BEGIN
	INSERT INTO bigtab VALUES (@x, 'x');
	SET @x = @x + 1;
END;
GO
DROP TABLE IF EXISTS bigtab2;
GO
SELECT * INTO bigtab2 FROM bigtab;
GO
SELECT [Current LSN], Operation, Context, AllocUnitName, [Transaction Name], *
FROM sys.fn_dblog(NULL, NULL)
GO