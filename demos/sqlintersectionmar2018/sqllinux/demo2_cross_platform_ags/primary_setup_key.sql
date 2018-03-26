-- You have to drop the endpoint before you can drop the certificate
-- You must delete the .cer and .pvk files if they already exist
DROP ENDPOINT hadr_endpoint
go
DROP CERTIFICATE dbm_certificate
go
DROP MASTER KEY
go
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Sql2017isfast';
go
CREATE CERTIFICATE dbm_certificate WITH SUBJECT = 'dbm';
go
-- Modify the path per your installation
--
BACKUP CERTIFICATE dbm_certificate
TO FILE = 'C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\MSSQL\DATA\dbm_certificate.cer'
WITH PRIVATE KEY (
        FILE = 'C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\MSSQL\DATA\dbm_certificate.pvk',
        ENCRYPTION BY PASSWORD = 'Sql2017isfast'
    );
GO