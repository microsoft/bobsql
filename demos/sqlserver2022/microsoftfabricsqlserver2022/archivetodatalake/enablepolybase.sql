EXEC sp_configure 'polybase enabled', 1;
GO
RECONFIGURE;
GO
EXEC sp_configure 'allow polybase export', 1;
GO
RECONFIGURE;
GO