USE [master];
GO
ALTER DATABASE [AdventureWorks]
SET READ_COMMITTED_SNAPSHOT OFF
WITH ROLLBACK IMMEDIATE;
GO
