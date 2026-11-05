USE master;
GO
DROP DATABASE IF EXISTS WideWorldImporters;
GO
RESTORE DATABASE WideWorldImporters FROM DISK = 'c:\sql_sample_databases\WideWorldImporters-Full.bak' with
MOVE 'WWI_Primary' TO 'c:\sql_sample_databases\WideWorldImporters.mdf',
MOVE 'WWI_UserData' TO 'c:\sql_sample_databases\WideWorldImporters_UserData.ndf',
MOVE 'WWI_Log' TO 'c:\sql_sample_databases\WideWorldImporters.ldf',
MOVE 'WWI_InMemory_Data_1' TO 'c:\sql_sample_databases\WideWorldImporters_InMemory_Data_1',
stats=5;
GO
ALTER DATABASE WideWorldImporters SET QUERY_STORE CLEAR ALL;
GO