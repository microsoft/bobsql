USE MASTER
GO
CREATE CREDENTIAL [s3://<local IP>:9000/backups]
WITH IDENTITY = 'S3 Access Key',
SECRET = '<user>:<password>';
GO