USE MASTER;
GO
BACKUP DATABASE WideWorldImporters
TO URL = 's3://<local IP>:9000/backups/wwi.bak'
WITH CHECKSUM, FORMAT, INIT;
GO