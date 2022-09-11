# Exercise for the Link feature for Azure SQL Managed Instance and SQL Server 2022

The following are steps for an exercise for the Link feature for Azure SQL Managed Instance with SQL Server 2022.

## Prereqs

- An Azure SQL Managed Instance deployed in the preview program to ensure it is compatible with SQL Server 2022.
- Create an Azure Storage account with a container to store SQL backups.
- A virtual machine or computer with at least 2 CPUs and 8Gb RAM.
- SQL Server 2022 Evaluation Edition.
- Azure network connectivity between SQL Server and Azure. If your SQL Server is running on-premises, use a VPN link or Express route. If your SQL Server is running on an Azure VM, either deploy your VM to the same subnet as your managed instance or use global VNet peering to connect two separate subnets.
- SQL Server Management Studio (SSMS). The latest 18.x build or 19.x build will work.
- Download the WideWorldImporters **Standard** sample backup from https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Standard.bak to the machine where you will run SQL Server. The Standard backup is used because it does not contain memory optimized tables which would not be supported if you chose the General Purpose service tier for Managed Instance.

## Preparing the environment

- Carefully go through each step at https://docs.microsoft.com/en-us/azure/azure-sql/managed-instance/managed-instance-link-preparation?view=azuresql.

## Create the link to replicate the database

1. Restore the WideWorldImporters database to SQL Server 2022 by executing the script **restorewwi_std.sql**. You may need to edit the file paths for the backup and your data and log files.
2. We need to change the recovery model to FULL and backup the database. Execute the script **fullandbackup.sql**.
3. Follow these steps to use SSMS to replicate the database to Managed Instance: https://docs.microsoft.com/en-us/azure/azure-sql/managed-instance/managed-instance-link-use-ssms-to-replicate-database?view=azuresql#replicate-a-database.
4. Using Object Explore view the status of the database is SYNCHRONIZED and expand the Always On Availability Group folder to see the AG and DAG created.
5. In the Azure Portal see the WideWorldImporters database is ONLINE in the main page of the Azure SQL Managed Instance.
6. In SSMS execute the script **checkstatus.sql** against the local SQL Server 2022 instance. Observe the updateability is READ_WRITE and the database version.
7. Connect to Azure SQL Managed Instance with SSMS and execute **checkstatus.sql** to see the updateability is READ_ONLY and database version is the same indicating compatibility between SQL Server and Azure SQL Managed Instance.

## View changes are replicated to Azure SQL Managed Instance

1. On the SQL Server 2022 instance execute the script **ddl.sql** and **populatedata.sql** to create two new tables and populate data.
2. Connect to Azure SQL Managed Instance and view the changes show up immediately by seeing the new tables and results by execute the script **getcargocounts.sql**.

## Failover to Azure SQL Managed Instance

1. Using the SSMS connection to the SQL Server 2022 instance execute a failover to Azure SQL Managed Instance using the steps at https://docs.microsoft.com/en-us/azure/azure-sql/managed-instance/managed-instance-link-use-ssms-to-failover-database?view=azuresql.
2. In SSMS run the query **checkstatus.sql** against the local SQL Server 2022 instance. Observe the updateability is READ_ONLY. Use Object Explorer to see the AG and DAG are removed.
3. Connect to Azure SQL Managed Instance and execute the script **checkstatus.sql** to see the updateability is READ_WRITE

## Restore a backup from Azure SQL Managed Instance back to SQL Server 2022

1. Use the steps at https://docs.microsoft.com/en-us/sql/relational-databases/tutorial-sql-server-backup-and-restore-to-azure-blob-storage-service?view=sql-server-ver16&tabs=SSMS to use SSMS connected to Azure SQL Managed Instance to backup the WideWorldImporters database to the Azure Storage account container you created in the prereqs.
2. Use the Azure Portal to view the backup in the Azure storage account container.
3. Using SSMS connect to the SQL Server 2022 instance follow the steps to restore the backup to a new database from Azure Blob Storage at https://docs.microsoft.com/en-us/sql/relational-databases/tutorial-sql-server-backup-and-restore-to-azure-blob-storage-service?view=sql-server-ver16&tabs=SSMS#restore-database.
