RESTORE FILELISTONLY FROM DISK = 'C:\sql_sample_databases\AdventureWorksLT2022.bak'
GO
RESTORE DATABASE AdventureWorksLT FROM DISK = 'C:\sql_sample_databases\AdventureWorksLT2022.bak'
WITH MOVE 'AdventureWorksLT2022_Data' TO 'c:\data\AdventureWorksLT.mdf',
MOVE 'AdventureWorksLT2022_Log' TO 'c:\data\AdventureWorksLT_log.ldf'
GO

