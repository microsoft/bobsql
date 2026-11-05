CREATE DATABASE letsgomavs;
GO
ALTER DATABASE letsgomavs SET RECOVERY FULL;
GO
BACKUP DATABASE letsgomavs
TO DISK = N'c:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Backup\letsgomavs.bak' WITH INIT;
GO