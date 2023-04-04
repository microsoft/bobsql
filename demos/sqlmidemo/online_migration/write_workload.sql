-- Perform writes
--
SELECT @@SERVERNAME AS SERVERNAME, CASE   
      WHEN SERVERPROPERTY('EngineEdition') < 5 THEN 'SQL Server'
	  WHEN SERVERPROPERTY('EngineEdition') = 8 THEN 'Azure SQL Mananaged Instance'
END   
GO
SELECT DATABASEPROPERTYEX('todo', 'Updateability');
GO
USE todo;
GO
SET NOCOUNT ON;
GO
DECLARE @x int;
SET @x = 0;
WHILE (@x < 10000000)
BEGIN
    INSERT INTO todolist (list_item, list_assigned) VALUES ('New todolist item', user_name());
    SET @x = @x + 1;
END;
GO
SET NOCOUNT OFF;
GO