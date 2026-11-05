-- Runtime credentials: SQLCMD variables; never save supplied values in source.
IF N'$(SqlLoginPassword)' = N'$' + N'(SqlLoginPassword)' OR LEN(N'$(SqlLoginPassword)') = 0
BEGIN
    RAISERROR('Supply SqlLoginPassword using SQLCMD mode. See SECRET-SCANNING.md. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END;
GO
USE [master]
GO
CREATE LOGIN [pacemakerLogin] with PASSWORD= N'$(SqlLoginPassword)'
GO
GRANT ALTER, CONTROL, VIEW DEFINITION ON AVAILABILITY GROUP::footballag TO pacemakerLogin
GO
GRANT VIEW SERVER STATE TO pacemakerLogin
GO
GO
SET NOEXEC OFF;
GO
