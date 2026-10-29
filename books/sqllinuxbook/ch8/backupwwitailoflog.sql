USE master
GO
BACKUP LOG WideWorldImporters TO DISK = '/var/opt/mssql/data/wwi_tailoflog.bak'
WITH INIT, NO_TRUNCATE, CHECKSUM
GO