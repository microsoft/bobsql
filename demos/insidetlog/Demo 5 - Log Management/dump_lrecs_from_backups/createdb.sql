USE MASTER;
GO
DROP DATABASE IF EXISTS findmytransaction;
GO
CREATE DATABASE findmytransaction;
GO
ALTER DATABASE [findmytransaction] SET QUERY_STORE = OFF;
GO
BACKUP DATABASE findmytransaction TO DISK = 'c:\temp\findmytransaction.bak' WITH INIT;
GO