USE master;
GO
CREATE LOGIN sqladmin WITH PASSWORD = '$Strongpassw0rd';
GO
EXEC sp_addsrvrolemember 'sqladmin', 'sysadmin';  
GO