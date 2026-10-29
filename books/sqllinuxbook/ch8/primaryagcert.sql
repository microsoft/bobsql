CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<REDACTED>'
GO
CREATE CERTIFICATE dbm_certificate WITH SUBJECT = 'dbm'
GO
BACKUP CERTIFICATE dbm_certificate
   TO FILE = '/var/opt/mssql/data/dbm_certificate.cer'
   WITH PRIVATE KEY (
           FILE = '/var/opt/mssql/data/dbm_certificate.pvk',
           ENCRYPTION BY PASSWORD = '<REDACTED>'
       )
GO