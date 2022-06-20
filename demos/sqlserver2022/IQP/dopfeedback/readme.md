# DOP Feedback in SQL Server 2022

This demo will show you how to see how to get consistent performance with less CPU resources for queries that require parallel operators

## Pre-requisites

- VM or computer with 8 CPUs and at least 24Gb RAM
- SQL Server 2022 CTP 2.0
- SQL Server Management Studio (SSMS) Version 19 Preview
- Download ostress.exe from https://www.microsoft.com/en-us/download/details.aspx?id=103126

## Steps

1. Execute configmaxdop.sql
1. Create a directory called c:\sql_sample_databases to store backups and files.
1. Copy the WideWorldImporters sample database from https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Full.bak to a local directory (The restore script assumes c:\sql_sample_databases)
1. Edit the restorewwi.sql script for the correct paths for the backup and where data and log files should go.
1. Execute the script restorewwi.sql
1. Extend the database by executing populatedata.sql. This will take ~13mins to execute. Because of the large transaction the log will grow to ~30Gb and the user FG will grow to about ~6.5Gb
1. Execute dopfeedback.sql to set QDS settings and db setting for DOP feeback (required for CTP 2.0)
1. Execute proc.sql to create a stored procedure
1. Execute dopexec.sql to create an XEvent session.
1. Use SSMS to Watch the XE session to see Live Data
1. Run workload_index_scan_users.cmd
1. Observe the XEvent data. It will take about 10mins to see XXXX event which means the final DOP setting to achieve stability.
1. Cancel the workload from the cmd script
1. Run dop_query_stats.sql to see the changes in DOP and resulting stats. Not the small decrease in avg duration and decrease in needed CPU
1. Use Top Resource Consuming Queries report and look at Avg Duration and Avg CPU to see the steady decrease until stable.
