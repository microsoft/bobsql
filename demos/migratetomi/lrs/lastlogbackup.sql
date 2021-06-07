USE master
GO
BACKUP LOG [baylorbearsnationalchamps]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/baylorbearsnationalchamps_last_log.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO




