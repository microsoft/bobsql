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
BACKUP DATABASE fullrecdb TO DISK = 'c:\temp\fullrecdb.bak' WITH INIT;
GO
BACKUP LOG fullrecdb TO DISK = 'c:\temp\fullrecdb_log.bak' WITH INIT;
GO
CHECKPOINT;
GO
DROP TABLE IF EXISTS bigtab2;
GO
SELECT * INTO bigtab2 FROM bigtab;
GO
SELECT [Current LSN], Operation, Context, AllocUnitName, [Log Record Length]
FROM sys.fn_dblog(NULL, NULL)
WHERE AllocUnitName = 'dbo.bigtab2';
GO