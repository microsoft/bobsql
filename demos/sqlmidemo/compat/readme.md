## Demo for compatibility of Azure SQL Managed Instance compared to SQL Server

This is a demo for compatibility of Azure SQL Managed Instance compared to SQL Server. You must have completed the exercises for online_migration before performing these demo steps.

## Steps

Follow these steps to show the compatibility of Azure SQL Managed Instance compared to SQL Server. Connect to SSMS to Azure SQL Managed Instance.

1. Load and execute the script **dbcompat.sql** to show the dbcompat level from the SQL Server 2019 database was maintained.
1. Load and execute the script **createagentjob.sql**. Notice the job has a T-SQL step to execute DBCC CHECKDB on the user database created as part of this demo.
1. Load and execute the script **dmvs.sql** to show common DMVs are available.
1. Load and execute **crossdb.sql** to show you can create new databases and execute cross-database queries.
1. Load and execute **querystore.sql** to show you can enable the Query Store and set all the options from SQL Server.
1. Using SSMS and Object Explorer, double-click on Standard under XEvent Profile to show you can use Extended Events in Managed Instance and even get a quick Live Watch of SQL activity.

