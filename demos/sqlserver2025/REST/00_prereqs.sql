EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
GO
EXEC sp_configure 'external rest endpoint enabled', 1;
RECONFIGURE;
