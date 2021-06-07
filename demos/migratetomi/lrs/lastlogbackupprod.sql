USE master
GO
BACKUP LOG [db1]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db1/db1log.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO
USE master
GO
BACKUP LOG [db2]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db2/db2log.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO
USE master
GO
BACKUP LOG [db3]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db3/db3log.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO
USE master
GO
BACKUP LOG [db4]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db4/db4log.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO
USE master
GO
BACKUP LOG [db5]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db5/db5log.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO
USE master
GO
BACKUP LOG [db6]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db6/db6log.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO
USE master
GO
BACKUP LOG [db7]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db7/db7log.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO
USE master
GO
BACKUP LOG [db8]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db8/db8log.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO
USE master
GO
BACKUP LOG [db9]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db9/db9log.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO
USE master
GO
BACKUP LOG [db10]
TO URL = 'https://bwmigratetoazurestorage.blob.core.windows.net/sqlbackups/db10/db10log.bak'
WITH INIT, COMPRESSION, CHECKSUM
GO




