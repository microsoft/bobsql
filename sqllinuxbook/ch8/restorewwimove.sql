RESTORE DATABASE WideWorldImporters
FROM DISK = '/var/opt/mssql/data/wwi.bak'
WITH MOVE 'WWI_Primary' to '/var/opt/mssql/WideWorldImporters.mdf',
MOVE 'WWI_UserData' to '/var/opt/mssql/WideWorldImporters_UserData.ndf',
MOVE 'WWI_Log' to '/var/opt/mssql/WideWordImporters.ldf',
MOVE 'WWI_InMemory_Data_1' to '/var/opt/mssql/WideWordImporters_InMemory_Data_1',
REPLACE
GO