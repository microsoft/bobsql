-- Run on SQL Server
-- Set full recovery mode for all databases you want to replicate.
ALTER DATABASE WideWorldImporters SET RECOVERY FULL;
GO
-- Execute backup for all databases you want to replicate.
BACKUP DATABASE WideWorldImporters TO DISK = N'c:\sql_sample_databases\wwi.bak';
GO