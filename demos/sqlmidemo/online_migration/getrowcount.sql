SELECT @@SERVERNAME AS SERVERNAME, CASE   
      WHEN SERVERPROPERTY('EngineEdition') < 5 THEN 'SQL Server'
	  WHEN SERVERPROPERTY('EngineEdition') = 8 THEN 'Azure SQL Mananaged Instance'
END   
GO
SELECT DATABASEPROPERTYEX('todo', 'Updateability');
GO
USE todo;
GO
SELECT COUNT(*) FROM todolist;
GO