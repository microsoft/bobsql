# Demo for an online migration from SQL Server 2019 to Azure SQL Managed Instance

This is a demo for an online migration from SQL Server 2019 to Azure SQL Managed Instance using the Managed Instance link feature. Follow all the prerequisites and setup instructions first at <https://github.com/microsoft/bobsql/blob/master/demos/sqlmidemo/readme.md>

## Synchronize SQL Server 2019 to Azure SQL Managed Instance

Follow these steps to synchronize your database to Azure SQL Managed Instance. After you sync the database see how you can use the Azure SQL Managed Instance

1. Carefully go through all the steps to prepare your SQL Server 2019 and Azure SQL Managed Instance to use the Managed Instance Link feature: <https://learn.microsoft.com/azure/azure-sql/managed-instance/managed-instance-link-preparation?view=azuresql>

> **Note:** Using the Azure marketplace for SQL Server 2019 automatically applies the latest CU for SQL Server 2019.

1. Follow these steps in SSMS to replicate the new database from SQL Server 2019 to Azure SQL Managed Instance: <https://learn.microsoft.com/azure/azure-sql/managed-instance/managed-instance-link-use-ssms-to-replicate-database?view=azuresql>

1. Connect to both SSMS and Azure SQL Managed Instance using SSMS so you see both connections in Object Explorer. Notice the database is marked Synchronized after you replicate it to Azure SQL Managed Instance. Notice also the database exists in Object Explore in the context of the Managed Instance.

1. Open the script **getrowcount.sql** for both SQL Server 2019 and Azure SQL Managed Instance. You can see the rowcounts for the todolist table are the same. You can also see the *updateability* of the todo database is READ_WRITE for SQL Server 2019 and READ_ONLY for Managed Instance. This shows the table data is synchronized.

1. Open up the script **write_workload.sql** connected to SQL Server 2019 and execute it. Now execute **getrowcount.sql** for Managed Instance. You can now see rowcount changes occur and shows you can use Managed Instance as a read replica while you are in the process of preparing to migrate.

1. Cancel the query execution for **write_workload.sql** to stop the write workload as you prepare to migrate.

## Perform the migration by executing a failover to Azure SQL Managed Instance

Follow these steps to perform an online migration from SQL Server 2019 to Azure SQL Managed Instance. These steps assume you have stopped the write workload as you did in the previous exercise.

1. Perform a failover to Azure SQL Managed Instance using the following steps in the documentation: <https://learn.microsoft.com/azure/azure-sql/managed-instance/managed-instance-link-use-ssms-to-replicate-database?view=azuresql>

2. Connect to Azure SQL Managed Instance and execute the script **getrowcount.sql** to show the new rowcounts and that the database is READ_WRITE on Managed Instance.

2. Load and execute the script **write_workload.sql** against Azure SQL Managed Instance to show you can now direct your write workloads to Azure SQL Managed Instance.
