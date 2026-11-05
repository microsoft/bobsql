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