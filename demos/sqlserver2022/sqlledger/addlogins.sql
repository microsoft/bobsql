USE master;
GO

-- Create a login for bob and make him a sysadmin
IF EXISTS (SELECT * FROM sys.server_principals WHERE NAME = 'bob')
BEGIN
DROP LOGIN bob;
END
CREATE LOGIN bob WITH PASSWORD = N'StrongPassw0rd!';
EXEC sp_addsrvrolemember 'bob', 'sysadmin';  
GO

-- Create a login for the app
IF EXISTS (SELECT * FROM sys.server_principals WHERE NAME = 'app')
BEGIN
DROP LOGIN app;
END
CREATE LOGIN app WITH PASSWORD = N'StrongPassw0rd!', DEFAULT_DATABASE = ContosoHR;
GO
