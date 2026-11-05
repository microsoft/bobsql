USE master;
GO
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$Strongpassw0rd';
GO
CREATE CERTIFICATE dbm_certificate WITH SUBJECT = 'dbm';
GO
BACKUP CERTIFICATE dbm_certificate
TO FILE = 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\dbm_certificate.cer'
WITH PRIVATE KEY (
FILE = 'c:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\dbm_certificate.pvk',
ENCRYPTION BY PASSWORD = '$Strongpassw0rd');
GO