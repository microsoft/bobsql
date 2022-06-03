# Link feature for Azure SQL Managed Instance and SQL Server 2022

The following are steps to demo the Link feature for Azure SQL Managed Instance with SQL Server 2022 CTP 2.x. In the future this demo will be enhanced to show the ability to failback to SQL Server 2022.

## Prereqs

- You have deployed an Azure SQL Managed Instance per the instructions of the Managed Instance engineering team
- SQL Server 2022 CTP 2.x Eval Edition (Dev Edition doesn't support AGs so you need Eval)
- Follow the steps to do all the prereqs for the computer or VM and local SQL Server instance at https://docs.microsoft.com/en-us/azure/azure-sql/managed-instance/managed-instance-link-use-ssms-to-replicate-database?view=azuresql. Carefully go through each step at https://docs.microsoft.com/en-us/azure/azure-sql/managed-instance/managed-instance-link-preparation?view=azuresql
- Latest SSMS 18.x build
- Create an Azure Storage account with a container.

## Demo steps

Use the following steps to demo the linked feature for Azure SQL Managed Instance and SQL Server 2002 CTP 2.x

### Replicate the database to Azure SQL Managed Instance

1. Restore the WideWorldImporters sample Standard database backup from https://github.com/Microsoft/sql-server-samples/releases/tag/wide-world-importers-v1.0 to the local SQL Server instance
2. Use the fullandbackup.sql script to set the recovery model to full and perform a full database backup.
3. Follow these steps to use SSMS to replicate the database to Managed Instance: https://docs.microsoft.com/en-us/azure/azure-sql/managed-instance/managed-instance-link-use-ssms-to-replicate-database?view=azuresql#replicate-a-database.
4. Using Object Explore view the status of the database is SYNCHRONIZED and expland the Always On Availability Group folder.
5. In the Azure Portal see the WideWorldImporters database is ONLINE in the maing page of the Azure SQL Managed Instance.
6. In SSMS run the query checkstatus.sql against the local SQL Server 2022 instance. Observe the updateability is READ_WRITE and the Version number.
7. Connect to Azure SQL Managed Instance and run the same query and see the updateability is READ_ONLY and Version number is the same indicating compatibility between SQL Server and Azure SQL Managed Instance.

### View changes are replicaed to Azure SQL Managed Instance

1. On the local SQL Server 2022 instance run the script ddl.sql and populatedata.sql
2. Connect to Azure SQL Managed Instance and view the changes show up immediately by seeing the new tables in Object Explorer and runnig the script getcargocounts.sql

### Restore a backup from Azure SQL Managed Instance back to SQL Server 2022

1. Use the steps at https://docs.microsoft.com/en-us/sql/relational-databases/tutorial-sql-server-backup-and-restore-to-azure-blob-storage-service?view=sql-server-ver16&tabs=SSMS to use SSMS connected to Azure SQL Managed Instance to backup the WideWorldImporters database to the Azure Storage account container you created in the prereqs.
2. Use the Azure Portal to view the backup in the Azure storage account container.
3. Using the SSMS connect to the SQL Server 2022 instance follow the steps to restore the backup to a new database from Azure Blob Storage at https://docs.microsoft.com/en-us/sql/relational-databases/tutorial-sql-server-backup-and-restore-to-azure-blob-storage-service?view=sql-server-ver16&tabs=SSMS#restore-database

### Failover to Azure SQL Managed Instance

1. Using the SSMS connection to the SQL Server 2022 instance execute a failover to Azure SQL Managed Instance using the steps at https://docs.microsoft.com/en-us/azure/azure-sql/managed-instance/managed-instance-link-use-ssms-to-failover-database?view=azuresql
2. In SSMS run the query checkstatus.sql against the local SQL Server 2022 instance. Observe the updateability is READ_ONLY and the Version number.
3. Connect to Azure SQL Managed Instance and run the same query and see the updateability is READ_WRITE and Version number is the same indicating compatibility between SQL Server and Azure SQL Managed Instance.
