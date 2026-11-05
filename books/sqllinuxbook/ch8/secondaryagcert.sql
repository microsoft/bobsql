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
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$(MasterKeyPassword)'
GO
CREATE CERTIFICATE dbm_certificate
    AUTHORIZATION dbm_user
    FROM FILE = '/var/opt/mssql/data/dbm_certificate.cer'
    WITH PRIVATE KEY (
    FILE = '/var/opt/mssql/data/dbm_certificate.pvk',
    DECRYPTION BY PASSWORD = '$(CertificatePassword)'
)
GO
GO
SET NOEXEC OFF;
GO
