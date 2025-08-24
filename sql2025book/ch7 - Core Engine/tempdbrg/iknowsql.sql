USE MASTER;
GO

-- Check if the database exists
IF EXISTS (SELECT name FROM sys.databases WHERE name = N'iknowsqldb')
BEGIN
    -- Set the database to single-user mode with rollback immediate
    ALTER DATABASE [iknowsqldb] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;

    -- Drop the database
    DROP DATABASE IF EXISTS [iknowsqldb];

END
ELSE
BEGIN
    PRINT 'Database iknowsqldb does not exist.';
END


-- Create the database
CREATE DATABASE iknowsqldb;
GO

-- Use the database
USE iknowsqldb;
GO

DROP TABLE IF EXISTS iknowsql;
GO

-- Create the table
CREATE TABLE iknowsql (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(50),
    Age INT,
    City NVARCHAR(50)
);
GO

-- Insert 1000 rows of sample data
DECLARE @i INT = 1;

WHILE @i <= 1000
BEGIN
    INSERT INTO iknowsql (Name, Age, City)
    VALUES (CONCAT('Name', @i), (RAND() * 60 + 20), CONCAT('City', @i % 100));
    SET @i = @i + 1;
END;
GO

-- Create a stored procedure that uses a temporary table
CREATE PROCEDURE ProcessData
AS
BEGIN
    -- Create a temporary table
    CREATE TABLE #TempTable (
        ID INT,
        Name NVARCHAR(50),
        Age INT,
        City NVARCHAR(50)
    );

    -- Insert data into the temporary table
    INSERT INTO #TempTable
    SELECT * FROM iknowsql;

    -- Process data in the temporary table (example: count rows)
    -- Do whatever processing else you need from here
    SELECT COUNT(*) AS CountPeople FROM #TempTable;

    -- Drop the temporary table
    DROP TABLE #TempTable;
END;
GO
