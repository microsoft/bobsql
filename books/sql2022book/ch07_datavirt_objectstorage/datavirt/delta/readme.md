# Demo for Data Virtualization using S3 providers for SQL Server 2022 for delta

This is a demonstration of data virtualization in SQL Server 2022 using the new REST API "connector" for S3 object storage for delta tables. If you want to see the results of this demo without going through all the steps of the exercise you can use Azure Data Studio or a web browser to view the **querydelta.ipynb** file.

**IMPORTANT**: If you have already completed all the steps for the demo for parquet you can skip all the prerequisites and steps to setup minio, except you will need to create a bucket called **delta** instead of wwi and follow the steps to upload a folder for the delta table in minio as described below in the section titled **Steps to use minio for the demo**. You can also skip to Step 8 to start using delta in the section below titled **Steps to use SQL Server for the demo for delta tables.**

**Note**: This demo uses non-Microsoft software that has "free" license to use for testing and development purposes only. This demo should only be run in a testing environment and not with any production workload.

## Prerequisites

- SQL Server 2022 Evaluation Edition with the Database Engine and PolyBase Query Service for External Data Feature installed. You can use the defaults in setup for Polybase.
- VM or computer with 2 CPUs and at least 8Gb RAM.
- SQL Server Management Studio (SSMS). The latest 18.x build or 19.x build will work.

**Note**: The following pre-requisites are for non-Microsoft software. The use of this software does not represent any official endorsement from Microsoft. This software is not supported by Microsoft so any issues using this software are up to the user to resolve.

- The **minio** server for Windows which you can download at https://min.io/download#/windows. For the demo I assume you have created a directory called c:\minio and have downloaded the minio.exe for Windows into that directory.
- openssl for Windows which you can download at https://slproweb.com/products/Win32OpenSSL.html. I chose the Win64 OpenSSL v3.0.5 MSI option.

## Setup minio for the demo

- Download minio.exe for Windows into c:\minio.exe
- Download the openssl for Windows MSI and run the installer. Use all the defaults.
- Set a system environment variable OPENSSL_CONF=C:\Program Files\OpenSSL-Win64\bin\openssl.cfg and add to the system environment variable PATH c:\Program Files\OpenSSL-Win64\bin
- Generate a private key using the following command from the c:\minio directory.

`openssl genrsa -out private.key 2048`

- Copy the supplied openssl.conf to c:\minio. Edit openssl.conf by changing IP.2 to your local IP address and DNS.2 to your local computer name.
- From the c:\minio directory run the following command to generate a self-signed certificate

`openssl req -new -x509 -nodes -days 730 -key private.key -out public.crt -config openssl.conf`

- Double-click the public.crt file and select Install Certificate. Choose Local Machine, Place all certificates in the following store, Browse, and select Trusted Root Certification Authorities.
- Copy the private.key and public.crt files from c:\minio into %%USERPROFILE%%\.minio\certs.

## Steps to use minio for the demo

1. From a command prompt at the c:\minio directory start the minio server with the following command (example syntax for Powershell)

.\minio.exe server c:\minio --console-address ":9001"

This program will startup and "run forever" until stopped with <Ctrl>+<C>. Your output should look similar to the following (the IP addresses will match your local IP):

```
MinIO Object Storage Server
Copyright: 2015-2022 MinIO, Inc.
License: GNU AGPLv3 <https://www.gnu.org/licenses/agpl-3.0.html>
Version: RELEASE.2022-07-30T05-21-40Z (go1.18.4 windows/amd64)

Status:         1 Online, 0 Offline.
API: https://<local IP>:9000  https://127.0.0.1:9000
RootUser: <user>
RootPass: <password>
Console: https://<local IP>:9001 https://127.0.0.1:9001
RootUser: <user>
RootPass: <password>

Command-line: https://docs.min.io/docs/minio-client-quickstart-guide
   $ mc.exe alias set myminio https://<local IP>:9000 <user> <password>
``
Documentation: https://docs.min.io
```
1. Test your connection and browse the minio storage system using a web browser. Use the address https://127.0.0.1:9001. You should be presented with a login screen. Use the defaut root user and password which are displayed on the minio server screen.

1. On the left-hand side menu, click on Identity and Users. Select Create User. Create a user name with password. Select the readwrite policy for the user. This is the user and password you will use for the SECRET value in creates3creds.sql.

3. Select menu for Buckets. Select Create Bucket. Use a Bucket Name of **delta**. Leave all defaults and select Create Bucket. From this bucket Browse, Upload, Upload folder. Choose the **people-10m** folder provides with this exercise. This will upload all the files and folders for the delta table.

**Note**: The people-10m delta table is a sample delta table from a sample dataset from Databricks as found at https://docs.microsoft.com/en-us/azure/databricks/data/databricks-datasets#sql. This dataset contains names, birthdates, and SSN which are all fictional and don't represent actual people. This dataset falls under the creative commons license at http://creativecommons.org/licenses/by/4.0/legalcode and can be shared and provided in this repo.

## Steps to use SQL Server for the demo for delta tables

1. Copy the **WideWorldImporters** sample database from https://aka.ms/WideWorldImporters to a local directory (The restore script assumes **c:\sql_sample_databases**)
1. Edit the **restorewwi.sql** script for the correct paths for the backup and where data and log files should go.
1. Execute the script **restorewwi.sql**.
1. Execute the script **enablepolybase.sql** to enable the Polybase feature for the instance.
1. Execute the script **createmasterkey.sql** to create a master key to protect a database scoped credential.
1. Edit the script **creates3creds.sql** to put in your user and password. Execute the script creates3creds.sql to create a database scoped credential. This contains the S3 user and password you created earlier with the minio console.
1. Edit the script **creates3datasource.sql** to substitute in your local IP address for the minio server. Execute the script creates3datasource.sql.
1. Create a file format to use for Parquet by executing the script **createparquetfileformat.sql**.
1. Query the delta table uploaded to the s3 storage under the delta bucket by executing the script **querydeltatable.sql**. There is 10m rows in the delta table so this query will take around 1 minute to execute.
1. This delta table was built with a partition column for the id column (default partitioning). First filter on a column not partitioned by executing the script **querybyssn.sql**. It should complete with about 4 seconds.
1. Now query by id to see if it is faster by executing the script **querybyid.sql**. Even though we used an id value in the query that was the highest one, the query still finishes in about 1 second because the delta table is partitioned on the id column.
1. Use CETAS to query the delta file and only extract a certain set of people to create a new folder by executing the script **createparquetfromdelta.sql**.
1. Use the minio console to browse the delta bucket and see a new folder called 1960s with multiple parquet files.
1. Query the new external table by executing the script **query1960speople.sql**

