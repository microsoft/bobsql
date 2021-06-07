USE master
GO
BACKUP DATABASE [db1]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db1/db1.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO
BACKUP DATABASE [db2]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db2/db2.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO
BACKUP DATABASE [db3]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db3/db3.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO
BACKUP DATABASE [db4]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db4/db4.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO
BACKUP DATABASE [db5]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db5/db5.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO
BACKUP DATABASE [db6]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db6/db6.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO
BACKUP DATABASE [db7]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db7/db7.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO
BACKUP DATABASE [db8]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db8/db8.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO
BACKUP DATABASE [db9]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db9/db9.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO
BACKUP DATABASE [db10]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db10/db10.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO
