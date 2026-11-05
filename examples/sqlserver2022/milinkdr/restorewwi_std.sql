USE master;
GO
RESTORE DATABASE WideWorldImporters FROM DISK = 'c:\sql_sample_databases\WideWorldImporters-Standard.bak' WITH
MOVE 'WWI_Primary' TO 'f:\data\WideWorldImporters.mdf',
MOVE 'WWI_UserData' TO 'f:\data\WideWorldImporters_UserData.ndf',
MOVE 'WWI_Log' TO 'g:\log\WideWorldImporters.ldf',
stats=5;
GO