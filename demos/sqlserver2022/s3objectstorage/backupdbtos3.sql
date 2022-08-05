USE MASTER;
GO
ALTER DATABASE WideWorldImporters SET RECOVERY FULL;
GO
BACKUP DATABASE WideWorldImporters
TO URL = 's3:/<local IP>:9000/backups/wwi.bak'
WITH CHECKSUM, INIT, FORMAT;
GO
BACKUP DATABASE WideWorldImporters
TO URL = 's3://<local IP>:9000/backups/wwidiff.bak'
WITH CHECKSUM, INIT, FORMAT, DIFFERENTIAL
GO
BACKUP LOG WideWorldImporters
TO URL = 's3://<local IP>:9000/backups/wwilog.bak'
WITH CHECKSUM, INIT, FORMAT
GO
BACKUP DATABASE WideWorldImporters
FILE = 'WWI_UserData'
TO URL = 's3://<local IP>:9000/backups/wwiuserdatafile.bak'
WITH CHECKSUM, INIT, FORMAT;
GO