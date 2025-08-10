RESTORE FILELISTONLY FROM DISK = 'C:\sql_sample_databases\AdventureWorks2022.bak'
GO
RESTORE DATABASE AdventureWorks FROM DISK = 'C:\sql_sample_databases\AdventureWorks2022.bak'
WITH MOVE 'AdventureWorks2022' TO 'c:\data\AdventureWorks.mdf',
MOVE 'AdventureWorks2022_Log' TO 'c:\data\AdventureWorks_log.ldf'
GO