BACKUP DATABASE bulklogdb TO DISK = 'c:\temp\bulklogdb.bak' WITH INIT;
GO
BACKUP LOG bulklogdb TO DISK = 'c:\temp\bulklogdb_log.bak' WITH INIT;
GO