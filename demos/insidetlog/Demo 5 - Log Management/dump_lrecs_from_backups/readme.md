# Show how to use sys.fn_db_dump_log()

1. Create and backup a database with the following statements:

USE MASTER;
GO
DROP DATABASE IF EXISTS findmytransaction;
GO
CREATE DATABASE findmytransaction;
GO
-- Turn off QDS to reduce log records
ALTER DATABASE findmytransaction SET
BACKUP DATABASE findmytrasaction TO DISK = 'c:\temp\findmytransaction.bak' WITH INIT;
GO

2. Create a table and insert some data in a transaction

USE findmytransaction;
GO
DROP TABLE IF EXISTS atablewithdata;
GO
CREATE TABLE atablewithdata (col int)
GO
BEGIN TRAN mytransaction;
GO
INSERT INTO atablewithdata(1);
INSERT INTO atablewithdata(2);
GO

Leave this query window open

3. Run this query to see the transaction in the log

USE findmytransaction;
GO
SELECT [Transaction Name], [Mark Name], [Operation], [Transaction ID]
FROM sys.fn_dblog(NULL, NULL),
	(SELECT [Transaction ID] tid
	FROM sys.fn_dblog(NULL, NULL)
	WHERE [Transaction Name] = 'mytransaction') [tran]
WHERE [tran].[tid] = [Transaction ID]
GO

3. Backup the log using the following statements

BACKUP LOG findmytransaction TO DISK = 'c:\temp\findmytransaction_log1.bak' WITH INIT;
GO

4. In the same query window run the delete and commit the tran

-- Run this delete after the 1st log backup
--
DELETE FROM atablewithdata;
COMMIT TRAN mytransaction;
GO

5. Backup the log again with this statements

BACKUP LOG findmytransaction TO DISK = 'c:\temp\findmytransaction_log2.bak' WITH INIT;
GO

6. Try to find the transaction

USE findmytransaction;
GO
SELECT [Transaction Name], [Mark Name], [Operation], [Transaction ID]
FROM sys.fn_dblog(NULL, NULL),
	(SELECT [Transaction ID] tid
	FROM sys.fn_dblog(NULL, NULL)
	WHERE [Transaction Name] = 'mytransaction') [tran]
WHERE [tran].[tid] = [Transaction ID]
GO

You see the transaction is gone because the log is truncated. How can I figure out how the table became empty?

7. Now try to find the transaction in the first backup using the following statement:

SELECT [Transaction Name], [Transaction ID],[Operation], * FROM
    fn_dump_dblog (
        NULL, NULL, N'DISK', 1, N'c:\temp\findmytransaction_log1.bak',
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT),
	(SELECT [Transaction ID] tid FROM
    fn_dump_dblog (
        NULL, NULL, N'DISK', 1, N'c:\temp\findmytransaction_log1.bak',
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT)
	WHERE [Transaction Name] = 'mytransaction') [tran]
WHERE [tran].[tid] = [Transaction ID];
GO

You can see only the start of the tran and the 2 INSERTs are there

8. Let's now try to find our DELETE and COMMIT in the 2nd log backup

SELECT [Mark Name], [Transaction ID],[Operation], * FROM
    fn_dump_dblog (
        NULL, NULL, N'DISK', 1, N'c:\temp\findmytransaction_log2.bak',
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT),
	(SELECT [Transaction ID] tid FROM
    fn_dump_dblog (
        NULL, NULL, N'DISK', 1, N'c:\temp\findmytransaction_log2.bak',
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT)
	WHERE [Mark Name] = 'mytransaction') [tran]
WHERE [tran].[tid] = [Transaction ID];
GO

You can now see the DELETE and COMMIT and have an exact timestamp when it occured

## Log growth and truncation


## Rebuliding the log

1. Create a new database like this:

USE master;
GO
DROP DATABASE IF EXISTS showmethemoney;
GO
CREATE DATABASE showmethemoney;
GO

2. Create a table and populate it with data like this

USE showmethemoney;
GO
DROP TABLE IF EXISTS bankaccount;
GO
CREATE TABLE bankaccount (acctno INT, name nvarchar(30), balance decimal(10,2))
GO
BEGIN TRAN
INSERT INTO bankaccount VALUES (1, 'Bob Ward', 1000000);
GO
-- I forgot to roll back this back. Ooops...
-- No problem recovery will do this for me
CHECKPOINT;
Go
USE MASTER;
GO

1. Kill the SQLSERVR.EXE process

4. Find the transaction log file and delete it

5. Restart SQL Server

6. In a new query window in master try this command

USE showmethemoney;
GO

You should see an error that the database is not avaialable.

7. Check the ERRORLOG for errors

8. Let's try to rebuild the log to bring db online

USE MASTER;
GO
ALTER DATABASE [showmethemoney] SET EMERGENCY;
GO
ALTER DATABASE [showmethemoney] SET SINGLE_USER;
GO
DBCC CHECKDB (N'showmethemoney', REPAIR_ALLOW_DATA_LOSS) WITH ALL_ERRORMSGS, NO_INFOMSGS;
GO

Show the errors and results

9. Check database status

10. From master execute this

USE MASTER;
GO
ALTER DATABASE [showmethemoney] SET MULTI_USER;
GO

11. Now execute this

USE showmethemoney;
GO
-- Uh oh
SELECT * FROM bankaccount;
GO