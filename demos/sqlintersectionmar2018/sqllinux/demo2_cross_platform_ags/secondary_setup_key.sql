DROP CERTIFICATE dbm_certificate
go
DROP MASTER KEY
go
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Sql2017isfast'
go
CREATE CERTIFICATE dbm_certificate   
    AUTHORIZATION dbm_user
    FROM FILE = '/var/opt/mssql/data/dbm_certificate.cer'
    WITH PRIVATE KEY (
    FILE = '/var/opt/mssql/data/dbm_certificate.pvk',
    DECRYPTION BY PASSWORD = 'Sql2017isfast'
)
go
