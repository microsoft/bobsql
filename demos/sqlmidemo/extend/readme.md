# Demo to see how to extend your Azure SQL Managed Instance migration

You can extend your migration of Azure SQL Managed Instance with the power of built-in capabilities like the following examples:

- Extend security through Azure Active Directory (AAD) authentication, managed identities, and Microsoft Defender.
- Use dbcompat 160 to take advantage of new Intelligent Query Processing (IQP) capabilities to get faster with no code changes.
- Access data lakes through T-SQL with data virtualization.

## Extend Security

1. Use the Azure Portal to see how you can configure AAD including AAD only.

2. Use the Azure Portal to see how you can configure managed identity to go *passwordless*

3. Use the Azure Portal to see how Microsoft Defender can look at possible vulnerabilities or detect SQL injection attacks.

## Get faster with no code changes with Intelligent Query Processing

Intelligent Query Process (IQP) are built-in capabilities in the SQL Server engine to get you faster with no code changes. Some of these capabilities are enabled by using the latest dbcompat level. If you remember when we migrated SQL Server 2019 the dbcompat level of the database was 150. By changing to dbcompat 160 we can enable features like Parameter Sensitive Plan Optimization (PSPO).

Parameter Sensitive Plans are scenarios where you may not seen consistent performance for the same stored procedure or parameterized query depending on parameter values and they skew of data used for queries.

To see an example how dbcompat 160 with Azure SQL Managed Instance can solve this problem go through the following example. All scripts for this example can be found in the **pspopt** directory.

1. Connect to your Azure SQL Managed Instance using SSMS.
1. Load and execute the script **setup.sql** to ensure the database is using dbcompat 150.
1. Load and execute the script **ddl.sql** to create a new table and load data. This can take several minutes to populate the data. Observe in the script how data is skewed regarding how many rows exist per list_id value.
1. Load and execute the script **proc.sql** to create a stored procedure used to access data in the table.
1. Using the "Including Actual Execution Plan" option (Ctrl+M) in a new query window load and execute the script **query_plan_seek.sql**. Look at the Execution Plan table and see an index seek is getting used.
1. Using the "Including Actual Execution Plan" option (Ctrl+M) in a new query window load and execute the script **query_plan_scan.sql**. Look at the Execution Plan table and see a clustered Index Scan is getting used for the same procedure but different parameter value. The script evicts plan cache to simulate a real-world scenario where the "first one to compile" wins.
1. Now execute **query_plan_seek.sql** again and see it now uses a Clustered Index Scan.
1. Enable Parameter Sensitive Plan Optimization by loading and execute the script **dbcompat160.sql**.
1. Repeat the same steps as before to execute **query_plan_seek.sql**, **query_plan_scan.sql**, and then **query_plan_seek.sql** again. You will see the 2nd execution of query_plan_seek.sql will use an Index Seek in the execution plan consistently.

## Access data lakes through data virtualization

Use data virtualization without any configuration to access data lakes such as parquet files in Azure through T-SQL OPENRWOSET or building external tables.

Using SSMS load and execute the T-SQL commands in the **openrowset.sql** script to see an example.