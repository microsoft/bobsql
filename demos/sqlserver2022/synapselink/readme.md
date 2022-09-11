# Exercise for Azure Synapse Link for SQL Server 2022

The following are steps for an exercise for Azure Synapse Link for SQL Server 2022 to allow easy integration of SQL Server data with Azure Synapse Analytics. The steps in this demo enhance the exercise to configure Synapse Link from the documentation at https://docs.microsoft.com/azure/synapse-analytics/synapse-link/connect-synapse-link-sql-server-2022.

## Prereqs

- A virtual machine or computer with at least 2 CPUs and 8Gb RAM.
- SQL Server 2022 Evaluation Edition
- An Azure subscription with permissions to create an Azure Synapse Workspace and Azure Data Lake Storage Gen2 account (Synapse uses one and you need a separate one for a concept called a Landing Zone).
- SQL Server Management Studio (SSMS). The latest 18.x build or 19.x build will work.
- Download the WideWorldImporters Standard sample backup from https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Standard.bak to the machine where you will run SQL Server. The Standard backup is used because features like In-memory OLTP are not supported with Synapse link.

## Setup the exercise

1. Create an Azure Synapse Analytics Workspace. For Network settings you must select Disable for Managed virtual network and check ON Allow connections from all IP address. If you are concerned about security you can setup firewall rules.
1. Create a dedicated SQL Pool with defaults.
1. Create a new Azure storage account to be used for Azure Data Lake Storage Gen2 which is the **Landing Zone**. You must check the Enable hierarchical namespace option. Create a container for this storage account. You now need to grant access for the Synapse workspace to the landing zone storage account. 

## Synchronize data with Synapse Link

1. Restore the WideWorldImporters standard backup using the script **restorewwi_std.sql**. You may need to edit the file paths for the backup and data and log files.
1. Add new tables to the SQL Server 2022 database by executing the script **extendwwitables.sql**.
1. Populate data into these tables by executing the script **populatedata.sql** against SQL Server.
1. Alter the SQL Server 2022 database to exclude unsupported features and data types by executing the script **alterwwi.sql**.
1. Create a master key on SQL Server 2022 by executing the script **creatmasterkey.sql**.
1. Use Synapse Studio and execute the SQL statement`CREATE MASTER KEY` against the SQL dedicated pool.
1. Use Synapse Studio to create schemas by executing the following SQL statements:


```tsql
CREATE SCHEMA Application;
GO
CREATE SCHEMA Purchasing;
GO
CREATE SCHEMA Sales;
GO
CREATE SCHEMA Warehouse;
GO
CREATE SCHEMA Website;
GO
```
1. 

