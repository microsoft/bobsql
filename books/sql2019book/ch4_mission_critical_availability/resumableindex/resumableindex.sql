-- Step 1: Create the database
USE master
GO
DROP DATABASE IF EXISTS gotexasrangers
GO
CREATE DATABASE gotexasrangers
GO

-- Step 2: Create a table as a heap with no clustered index
-- Make the table fairly big so an index build takes at least
-- a few minutes. The resumable index option for MAX_DURATION has
-- a minimum value of 1 minute.
USE gotexasrangers
GO
DROP TABLE IF EXISTS letsgorangers
GO
CREATE TABLE letsgorangers (col1 int, col2 char(7000) not null)
GO
SET NOCOUNT ON
GO
BEGIN TRAN
GO
INSERT INTO letsgorangers values (1, 'I would love to win the World Series')
GO 750000
COMMIT TRAN
GO
SET NOCOUNT OFF
GO

-- Step 3: Try to create the index as online, resumable, and a max_duration of 1 minute
CREATE CLUSTERED INDEX rangeridx ON letsgorangers (col1) WITH (ONLINE = ON, RESUMABLE = ON, MAX_DURATION = 1)
GO

-- Step 4: Check the progress of the index build
USE gotexasrangers
GO
SELECT * FROM sys.index_resumable_operations
GO

-- Step 5: Resume the index build
ALTER INDEX rangeridx on letsgorangers RESUME
GO

-- Step 6: Drop the first index. Use the default scoped option for resumable and online
USE gotexasrangers
GO
ALTER DATABASE SCOPED CONFIGURATION SET ELEVATE_RESUMABLE = WHEN_SUPPORTED
GO
ALTER DATABASE SCOPED CONFIGURATION SET ELEVATE_ONLINE = WHEN_SUPPORTED
GO
DROP INDEX IF EXISTS letsgorangers.rangeridx
GO

-- Step 7: Create the index again. Notice there are no options used.
-- CANCEL this after about 30 seconds
CREATE CLUSTERED INDEX rangeridx ON letsgorangers (col1)
GO

-- Step 8: Check the index progress
USE gotexasrangers
GO
SELECT * FROM sys.index_resumable_operations
GO

-- Step 9: Resume the index build
ALTER INDEX rangeridx on letsgorangers RESUME
GO