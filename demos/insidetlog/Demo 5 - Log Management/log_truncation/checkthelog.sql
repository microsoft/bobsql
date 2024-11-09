USE letsgostars;
GO
SELECT * FROM sys.dm_db_log_info(NULL);
GO
SELECT name, log_reuse_wait_desc
FROM sys.databases
WHERE name = 'letsgostars';
GO

