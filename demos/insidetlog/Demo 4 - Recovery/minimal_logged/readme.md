# Demo for minimially logged transactions

1. Create the minimally logged database

USE MASTER;
GO
DROP DATABASE IF EXISTS bulklogdb;
GO
CREATE DATABASE bulklogdb;
GO
ALTER DATABASE bulklogdb
SET RECOVERY BULK_LOGGED;
GO
ALTER DATABASE bulklogdb
SET QUERY_STORE = OFF;
GO

2. Create a table and populate some rows

USE bulklogdb;
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
BACKUP DATABASE bulklogdb TO DISK = 'c:\temp\bulklogdb.bak' WITH INIT;
GO

2. Run a SELECT INTO and look at logrecs

use bulklogdb;
GO
DROP TABLE IF EXISTS bigtab2;
GO
SELECT * INTO bigtab2 FROM bigtab;
GO
SELECT [Current LSN], Operation, Context, AllocUnitName, [Transaction Name], *
FROM sys.fn_dblog(NULL, NULL)
GO

3. Now do the same for a full recovery db

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

