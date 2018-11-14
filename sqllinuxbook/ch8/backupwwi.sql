USE master
GO
BACKUP DATABASE WideWorldImporters
TO DISK = '/var/opt/mssql/data/wwi.bak'
WITH INIT, STATS=5, CHECKSUM
GO