USE master
GO
BACKUP DATABASE [baylorbearsnationalchamps]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/baylorbearsnationalchamps.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO

