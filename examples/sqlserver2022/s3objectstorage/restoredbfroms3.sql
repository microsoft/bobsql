USE MASTER;
GO
RESTORE VERIFYONLY FROM URL = 's3://<local IP>:9000/backups/wwi.bak';
GO
RESTORE HEADERONLY FROM URL = 's3://<local IP>:9000/backups/wwi.bak';
GO
RESTORE FILELISTONLY FROM URL = 's3://<local IP>:9000/backups/wwi.bak';
GO
DROP DATABASE IF EXISTS WideWorldImporters2;
GO
RESTORE DATABASE WideWorldImporters2 
FROM URL = 's3://<local IP>:9000/backups/wwi.bak'
WITH MOVE 'WWI_Primary' TO 'c:\sql_sample_databases\WideWorldImporters2.mdf',
MOVE 'WWI_UserData' TO 'c:\sql_sample_databases\WideWorldImporters2_UserData.ndf',
MOVE 'WWI_Log' TO 'c:\sql_sample_databases\WideWorldImporters2.ldf',
MOVE 'WWI_InMemory_Data_1' TO 'c:\sql_sample_databases\WideWorldImporters2_InMemory_Data_1';
GO