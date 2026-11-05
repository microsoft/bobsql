USE master
GO
BACKUP DATABASE WideWorldImporters
TO DISK = '/var/opt/mssql/data/wwi_diff1.bak'
WITH INIT, DIFFERENTIAL, CHECKSUM
GO