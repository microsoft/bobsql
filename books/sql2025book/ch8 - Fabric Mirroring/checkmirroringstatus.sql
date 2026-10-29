USE AdventureWorksLT;
GO
EXEC sp_help_change_feed;
GO
SELECT * FROM sys.dm_change_feed_log_scan_sessions;
GO
SELECT * FROM sys.dm_change_feed_errors;
GO