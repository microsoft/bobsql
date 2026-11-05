-- Runtime credentials: SQLCMD variables; never save supplied values in source.
IF N'$(MasterKeyPassword)' = N'$' + N'(MasterKeyPassword)' OR LEN(N'$(MasterKeyPassword)') = 0
BEGIN
    RAISERROR('Supply MasterKeyPassword using SQLCMD mode. See SECRET-SCANNING.md. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END;
GO
USE [WideWorldImporters];
GO
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$(MasterKeyPassword)';
GO
GO
SET NOEXEC OFF;
GO
