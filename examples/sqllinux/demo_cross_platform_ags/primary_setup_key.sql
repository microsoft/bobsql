-- Runtime credentials: SQLCMD variables; never save supplied values in source.
IF N'$(CertificatePassword)' = N'$' + N'(CertificatePassword)' OR LEN(N'$(CertificatePassword)') = 0
BEGIN
    RAISERROR('Supply CertificatePassword using SQLCMD mode. See SECRET-SCANNING.md. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END;
GO
IF N'$(MasterKeyPassword)' = N'$' + N'(MasterKeyPassword)' OR LEN(N'$(MasterKeyPassword)') = 0
BEGIN
    RAISERROR('Supply MasterKeyPassword using SQLCMD mode. See SECRET-SCANNING.md. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
END;
GO
-- You have to drop the endpoint before you can drop the certificate
-- You must delete the .cer and .pvk files if they already exist
DROP ENDPOINT hadr_endpoint
go
DROP CERTIFICATE dbm_certificate
go
DROP MASTER KEY
go
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$(MasterKeyPassword)';
go
CREATE CERTIFICATE dbm_certificate WITH SUBJECT = 'dbm';
go
-- Modify the path per your installation
--
BACKUP CERTIFICATE dbm_certificate
TO FILE = 'C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\MSSQL\DATA\dbm_certificate.cer'
WITH PRIVATE KEY (
        FILE = 'C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\MSSQL\DATA\dbm_certificate.pvk',
        ENCRYPTION BY PASSWORD = '$(CertificatePassword)'
    );
GO
GO
SET NOEXEC OFF;
GO
