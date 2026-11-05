SELECT * FROM sys.dm_db_log_info(DB_ID('dbmediumlog'));
GO
SELECT * FROM sys.dm_db_log_info(DB_ID('dbbiglog'));
GO
SELECT * FROM sys.dm_db_log_info(DB_ID('dbbiggerlog'));
GO
SELECT * FROM sys.dm_db_log_info(DB_ID('dbgiganticlog'));
GO
