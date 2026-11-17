-- Connect directly to master as the Microsoft Entra administrator.
-- This is the App Service system-assigned managed identity's display name,
-- supplied as SQLCMD variable AppName by deploy\07-deploy-scheduling.ps1.
IF DB_NAME() <> N'master'
    THROW 50000, 'Connect directly to master before creating the app login.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$(AppName)')
    CREATE LOGIN [$(AppName)] FROM EXTERNAL PROVIDER;
GO
