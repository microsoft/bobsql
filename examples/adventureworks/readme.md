# BACPAC file for AdventureWorksLT database

This is a .bacpac file and script to import a BACPAC into an existing Azure SQL Database.

The adventureworkslt2025.bacpac file is based on the full backup https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorksLT2025.bak.

## Prerequisites

Install sqlpackage.exe by executing the following command

```
dotnet tool install -g microsoft.sqlpackage
```

## How to use the bacpac file

You can use the bacpac file to create a new database which is supported using SSMS, sqlpackage.exe, or az cli.

## How to import this into an existing database.

Use the script **importadwlt.cmd**

- Edit the script to put in your logical server
- The script assumes Entra Auth using MFA. Change the Authentication method if needed to meet your requirements.

When you execute this script against Azure SQL Database, you may see these warnings which can be ignored:

```*** A project which specifies SQL Server 2025 or Azure SQL Database Managed Instance as the target platform may experience compatibility issues with Microsoft Azure SQL Database v12.
*** The object [data_0] exists in the target, but it will not be dropped even though you selected the 'Generate drop statements for objects that are in the target database but that are not in the source' check box.
*** The object [log] exists in the target, but it will not be dropped even though you selected the 'Generate drop statements for objects that are in the target database but that are not in the source' check box`