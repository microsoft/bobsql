Here is syntax for backup


USE MASTER
GO
CREATE CREDENTIAL [s3://192.168.232.131:9000/backups]
WITH IDENTITY = 'S3 Access Key',
SECRET = 'wwiadmin:wwiadmin';

BACKUP DATABASE WideWorldImporters
TO URL = 's3://192.168.232.131:9000/backups/wwi.bak'

https://s3browser.com

