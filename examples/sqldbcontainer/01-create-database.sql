USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'CustomerServiceDesk')
    EXEC(N'CREATE DATABASE [CustomerServiceDesk];');
GO

SELECT name, state_desc, compatibility_level
FROM sys.databases
WHERE name = N'CustomerServiceDesk';
GO

USE CustomerServiceDesk;
GO

ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
GO

SELECT name, value
FROM sys.database_scoped_configurations
WHERE name = N'PREVIEW_FEATURES';
