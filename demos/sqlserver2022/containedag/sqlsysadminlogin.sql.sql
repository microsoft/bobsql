USE master;
GO
CREATE LOGIN sqladmin WITH PASSWORD = '<strong pwd>';
GO
EXEC sp_addsrvrolemember 'sqladmin', 'sysadmin';  
GO