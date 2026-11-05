USE [master];
GO
DROP DATABASE IF EXISTS [annaisasqlnewbie];
GO
CREATE DATABASE [annaisasqlnewbie];
GO
-- turn off Query store so it won't flush the log
ALTER DATABASE annaisasqlnewbie SET QUERY_STORE = OFF;
GO

