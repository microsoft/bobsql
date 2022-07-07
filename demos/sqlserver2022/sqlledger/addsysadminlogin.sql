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