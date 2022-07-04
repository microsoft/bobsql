USE master;
GO

-- Create the ContosoHR database
--
DROP DATABASE IF EXISTS ContosoHR;
GO
CREATE DATABASE ContosoHR;
GO
USE ContosoHR;
GO

-- Enable snapshot isolation to allow ledger to be verified
ALTER DATABASE ContosoHR SET ALLOW_SNAPSHOT_ISOLATION ON
GO

-- Create an app user for the app login
CREATE USER app FROM LOGIN app;
GO
EXEC sp_addrolemember 'db_owner', 'app'
GO