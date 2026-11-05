-- Runtime credentials: SQLCMD variables; never save supplied values in source.
IF N'$(SqlLoginPassword)' = N'$' + N'(SqlLoginPassword)' OR LEN(N'$(SqlLoginPassword)') = 0
BEGIN
    RAISERROR('Supply SqlLoginPassword using SQLCMD mode. See SECRET-SCANNING.md. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END;
GO
USE master
GO
IF EXISTS (select * from sys.server_principals where name = 'sqllinux')
    DROP LOGIN [sqllinux]
GO
CREATE LOGIN [sqllinux] WITH PASSWORD=N'$(SqlLoginPassword)', DEFAULT_DATABASE=[master]
GO
ALTER AUTHORIZATION ON DATABASE::WideWorldImporters to sqllinux
GO
GO
SET NOEXEC OFF;
GO
