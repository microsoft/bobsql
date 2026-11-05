USE MASTER;
GO

-- Check if the database exists
IF EXISTS (SELECT name FROM sys.databases WHERE name = N'guyinacubedb')
BEGIN
    -- Set the database to single-user mode with rollback immediate
    ALTER DATABASE [guyinacubedb] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;

    -- Drop the database
    DROP DATABASE IF EXISTS [guyinacubedb];

END
ELSE
BEGIN
    PRINT 'Database guyinacubedb does not exist.';
END

CREATE DATABASE guyinacubedb;
GO
USE guyinacubedb;
GO
DROP TABLE IF EXISTS bigtab;
GO
CREATE TABLE bigtab (col1 INT PRIMARY KEY CLUSTERED, col2 CHAR(5000) NOT NULL);
GO
SET NOCOUNT ON;
GO
BEGIN TRAN;
GO
DECLARE @i INT;
SET @i = 0;
WHILE (@i < 1000000)
BEGIN
	INSERT INTO bigtab VALUES (@i, 'Who is the original Guy in a Cube?');
	SET @i = @i + 1;
END
GO
COMMIT TRAN;
GO
SET NOCOUNT OFF;
GO