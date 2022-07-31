# Demo for data virtualization in SQL Server 2022

## Prereqs

Setup mino server

https://min.io/download#/windows


Or from Powershell just run this

```powershell
mkdir c:\minio
Invoke-WebRequest -Uri "https://dl.min.io/server/minio/release/windows-amd64/minio.exe" -OutFile "C:\minio\minio.exe"
cd \minio
.\minio.exe server c:\minio --console-address ":9001"
```

You may for the first time running this on Windows get a pop-up box for Windows Defender Firewall. Click Allow Access if you get this

You should see output like the following

Formatting 1st pool, 1 set(s), 1 drives per set.
WARNING: Host local has more than 0 drives of set. A host failure will result in data becoming unavailable.
lkjui\pof./ quick.

minio.exe is not a Windows Service. It is a command line program that "waits" for input just like if you ran sqlservr.exe from the command line.

This is all for testing purposes. Note this from the minio docs

NOTE: Standalone MinIO servers are best suited for early development and evaluation. Certain features such as versioning, object locking, and bucket replication require distributed deploying MinIO with Erasure Coding. For extended development and production, deploy MinIO with Erasure Coding enabled - specifically, with a minimum of 4 drives per MinIO server. See MinIO Erasure Code Quickstart Guide for more complete documentation.

Use your browser to go to http://127.0.0.1:9001/login

Put in minioadmin and minioadmin in the login screen

Use the createbucket screen to create a bucket called wwi

1. Install SQL with Database Engine Services and PolyBase Query Service for External Data Feature. Pick default for port range and PB Service Accounts.
1. Configure PB for SQL
 
EXEC SP_CONFIGURE @CONFIGNAME = 'POLYBASE ENABLED', @CONFIGVALUE = 1;

RECONFIGURE;

1. Create master key

DECLARE @randomWord VARCHAR(64) = NEWID();
DECLARE @createMasterKey NVARCHAR(500) = N'
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = ''##MS_DatabaseMasterKey##'')
	CREATE MASTER KEY ENCRYPTION BY PASSWORD = '  + QUOTENAME(@randomWord, '''')
EXECUTE sp_executesql @createMasterKey
GO

1. Create db scoped creds

USE WideWorldImporters
GO
--DATABASE SCOPED SCOPED CREDENTIAL
-----------------------------------
IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 's3_wwi_cred')
    DROP DATABASE SCOPED CREDENTIAL s3_wwi_cred
GO
CREATE DATABASE SCOPED CREDENTIAL s3_wwi_cred
WITH IDENTITY = 'S3 Access Key',
SECRET = 'minioadmin:minioadmin'
GO
SELECT * FROM sys.database_scoped_credentials
GO

1. Create the data source

-- CREATE EXTERNAL DATA SOURCE 
------------------------------
IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 's3_wwi')
	DROP EXTERNAL DATA SOURCE s3_wwi

CREATE EXTERNAL DATA SOURCE s3_wwi
WITH
(
 LOCATION = 's3://127.0.0.1:9001/wwi'
,CREDENTIAL = s3_wwi_cred
)
GO
SELECT * FROM sys.external_data_sources
GO

1. Create a file format

IF EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'ParquetFileFormat')
	DROP EXTERNAL FILE FORMAT ParquetFileFormat

CREATE EXTERNAL FILE FORMAT ParquetFileFormat WITH(FORMAT_TYPE = PARQUET);
GO

1. Create EXTERNAL TABLE with CETAS

CREATE EXTERNAL TABLE wwi_customer_transactions_files
WITH (
    LOCATION = '/wwi_customer_transactions',
    DATA_SOURCE = s3_wwi,  
    FILE_FORMAT = ParquetFileFormat
)  
AS
SELECT * FROM Sales.CustomerTransactions;
GO

Minio certs

1. oopenssl genrsa -out private.key 2048
1. 2. Create an openssl.conf file like this
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
			
[req_distinguished_name]
C = US
ST = TX
L = Somewhere
O = MyOrg
OU = MyOU
CN = MyServerName
			
[v3_req]
subjectAltName = @alt_names
			
[alt_names]
IP.1 = 127.0.0.1
IP.2=192.168.232.131
DNS.1 = localhost
DNS.2=minio.local

1. Now run this and enter in password from above when prompted: openssl req -new -x509 -nodes -days 730 -key private.key -out public.crt -config openssl.conf
1. Copy private.key and public.crt to \users\<user>\.minio\certs
1. Start minio server
1. 
1. 


Here is information on Delta

https://github.com/delta-io/delta