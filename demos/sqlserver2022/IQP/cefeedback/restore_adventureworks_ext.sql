DROP DATABASE IF EXISTS AdventureWorks_EXT;
GO
RESTORE FILELISTONLY FROM DISK = 'c:\sql_sample_databases\AdventureWorks2016_EXT.bak'
GO
RESTORE DATABASE AdventureWorks_EXT FROM DISK = 'c:\sql_sample_databases\AdventureWorks2016_EXT.bak'
WITH MOVE 'AdventureWorks2016_EXT_Data' TO 'c:\sql_sample_databases\AdventureWorks2016_Data.mdf',
MOVE 'AdventureWorks2016_EXT_Log' TO 'c:\sql_sample_databases\AdventureWorks2016_log.ldf',
MOVE 'AdventureWorks2016_EXT_Mod' TO 'c:\sql_sample_databases\AdventureWorks2016_EXT_mod'
GO