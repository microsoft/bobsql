-- Runtime credentials: SQLCMD variables; never save supplied values in source.
IF N'$(SqlLoginPassword)' = N'$' + N'(SqlLoginPassword)' OR LEN(N'$(SqlLoginPassword)') = 0
BEGIN
    RAISERROR('Supply SqlLoginPassword using SQLCMD mode. See SECRET-SCANNING.md. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END;
GO
USE master;
GO
-- Create a login for bob and make him a sysadmin
IF EXISTS (SELECT * FROM sys.server_principals WHERE NAME = 'bob')
BEGIN
DROP LOGIN bob;
END
CREATE LOGIN bob WITH PASSWORD = N'$(SqlLoginPassword)';
EXEC sp_addsrvrolemember 'bob', 'sysadmin';  
GO
GO
SET NOEXEC OFF;
GO
