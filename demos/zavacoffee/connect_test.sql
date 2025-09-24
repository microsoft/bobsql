-- Connectivity sanity checks for ZavaSCM (SQL Database)
-- Uses active connection profile in VS Code (ZavaSCM (SQL Database))

SELECT SYSDATETIMEOFFSET() AS ServerTime;
SELECT SUSER_SNAME() AS CurrentLogin, SYSTEM_USER AS SystemUser;
SELECT DB_NAME() AS CurrentDatabase;
SELECT TOP (10) name, create_date FROM sys.tables ORDER BY create_date DESC;
