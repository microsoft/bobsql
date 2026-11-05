RESTORE DATABASE WideWorldImporters FILEGROUP = 'Primary', FILEGROUP = 'WWI_InMemory_Data_1' 
FROM DISK = '/var/opt/mssql/data/wwi.bak'
WITH REPLACE, PARTIAL, NORECOVERY
GO
RESTORE DATABASE WideWorldImporters FROM DISK = '/var/opt/mssql/data/wwi_diff1.bak'
WITH NORECOVERY
GO
RESTORE LOG WideWorldImporters FROM DISK = '/var/opt/mssql/data/wwi_log3.bak'
WITH NORECOVERY
GO
RESTORE LOG WideWorldImporters FROM DISK = '/var/opt/mssql/data/wwi_tailoflog.bak'
WITH NORECOVERY
GO
RESTORE DATABASE WideWorldImporters WITH RECOVERY
GO