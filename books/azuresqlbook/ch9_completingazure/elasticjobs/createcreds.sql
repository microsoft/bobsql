IF N'$(JobCredentialSecret)' = N'$' + N'(JobCredentialSecret)' OR LEN(N'$(JobCredentialSecret)') = 0
BEGIN
    RAISERROR('Supply JobCredentialSecret in SQLCMD mode. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END;
GO
-- Runtime credentials: SQLCMD variables; never save supplied values in source.
IF N'$(MasterCredentialSecret)' = N'$' + N'(MasterCredentialSecret)' OR LEN(N'$(MasterCredentialSecret)') = 0
BEGIN
    RAISERROR('Supply MasterCredentialSecret using SQLCMD mode. See SECRET-SCANNING.md. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END;
GO
IF N'$(MasterKeyPassword)' = N'$' + N'(MasterKeyPassword)' OR LEN(N'$(MasterKeyPassword)') = 0
BEGIN
    RAISERROR('Supply MasterKeyPassword using SQLCMD mode. See SECRET-SCANNING.md. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END;
GO
-- Create a db master key if one does not already exist, using your own password.  
CREATE MASTER KEY ENCRYPTION BY PASSWORD='$(MasterKeyPassword)';
GO

-- Create a database scoped credential for the master database of server1.
CREATE DATABASE SCOPED CREDENTIAL mymastercred WITH IDENTITY = 'mastercred', SECRET = '$(MasterCredentialSecret)';
GO

-- Create a database scoped credential.  
CREATE DATABASE SCOPED CREDENTIAL myjobcred WITH IDENTITY = 'jobcred', SECRET = '$(JobCredentialSecret)';
GO
GO
SET NOEXEC OFF;
GO
