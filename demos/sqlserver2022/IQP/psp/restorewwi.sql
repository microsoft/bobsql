USE master;
GO
DROP DATABASE IF EXISTS WideWorldImporters;
GO
-- Edit the locations for files to match your storage
RESTORE DATABASE WideWorldImporters FROM DISK = 'c:\sql_sample_databases\WideWorldImporters-Full.bak' with
MOVE 'WWI_Primary' TO 'f:\data\WideWorldImporters.mdf',
MOVE 'WWI_UserData' TO 'f:\data\WideWorldImporters_UserData.ndf',
MOVE 'WWI_Log' TO 'g:\log\WideWorldImporters.ldf',
MOVE 'WWI_InMemory_Data_1' TO 'f:\data\WideWorldImporters_InMemory_Data_1',
stats=5;
go