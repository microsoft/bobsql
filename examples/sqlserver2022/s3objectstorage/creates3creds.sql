USE MASTER
GO
IF EXISTS (SELECT * FROM sys.credentials WHERE name = 's3://<local IP>:9000/backups')
	DROP CREDENTIAL [s3://<local IP>:9000/backups];
GO
CREATE CREDENTIAL [s3://<local IP>:9000/backups]
WITH IDENTITY = 'S3 Access Key',
SECRET = '<user>:<password>';
GO