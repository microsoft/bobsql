-- Step 1: Create the database and make it simple recovery. Default for ADR is OFF
USE master
GO
DROP DATABASE IF EXISTS gocowboys
GO
CREATE DATABASE gocowboys
GO
ALTER DATABASE gocowboys SET RECOVERY SIMPLE
GO

-- Step 2: Create a very basic table and insert 1000 rows
USE gocowboys
GO
DROP TABLE IF EXISTS howboutthemcowboys
GO
CREATE TABLE howboutthemcowboys (col1 int, col2 char(100) not null)
GO
INSERT INTO howboutthemcowboys VALUES (1, 'Whitten has returned')
GO 1000

-- Step 3: Truncate the log, delete all rows, roll it back, and look at the tlog records
CHECKPOINT
GO
BEGIN TRAN
DELETE FROM howboutthemcowboys
ROLLBACK TRAN
GO
SELECT * FROM sys.fn_dblog(NULL, NULL)
GO

-- Step 4: Change to use ADR for the db. Recreate the table again
ALTER DATABASE gocowboys SET ACCELERATED_DATABASE_RECOVERY = ON
GO
USE gocowboys
GO
DROP TABLE IF EXISTS howboutthemcowboys
GO
CREATE TABLE howboutthemcowboys (col1 int, col2 char(100) not null)
GO
INSERT INTO howboutthemcowboys VALUES (1, 'Whitten has returned')
GO 1000

-- Step 5: Delete and rollback and look at the tlog again
CHECKPOINT
GO
BEGIN TRAN
DELETE FROM howboutthemcowboys
ROLLBACK TRAN
GO
SELECT * FROM sys.fn_dblog(NULL, NULL)
GO

-- Step 6: Look at the PVS stats
SELECT * FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = db_id('gocowboys')
GO


