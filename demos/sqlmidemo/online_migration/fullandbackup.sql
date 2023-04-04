-- Run on SQL Server
-- Set full recovery mode for all databases you want to replicate.
ALTER DATABASE todo SET RECOVERY FULL;
GO
-- Execute backup for all databases you want to replicate.
BACKUP DATABASE todo TO DISK = N'C:\backups\todo.bak';
GO