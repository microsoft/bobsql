SELECT * FROM sys.dm_db_log_info(NULL);

DBCC TRACEON(2537);
GO

-- Put in here the previous active tran LSN
SELECT * FROM sys.fn_dblog('27:0:0', NULL);
GO