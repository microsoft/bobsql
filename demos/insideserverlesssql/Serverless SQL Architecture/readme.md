# Demo for looking at a Serverless SQL Pool SQL Server

This demo is intended to look behind the scenes at the SQL Server front-end used for queries for Serverless SQL Pools. All example queries will come from this tutorial in the documentation at https://docs.microsoft.com/en-us/azure/synapse-analytics/sql/tutorial-data-analyst

1. Deploy a Azure Synapse Analytics workspace

2. Explore Serverless SQL Pools in the Azure Portal

- Select SQL Pools from the Resource Menu and notice the "Built-in" name. Every new Azure Synapse Analytics workspace gets a "built-in" pool which is the Serverless SQL Pool
- On the Overview page, note the Serverless SQL endpoint URL.

2. In Synapse Studio, create a new SQL Script and run this query

```sql
SELECT TOP 100000 * FROM
    OPENROWSET(
        BULK 'https://azureopendatastorage.blob.core.windows.net/nyctlc/yellow/puYear=*/puMonth=*/*.parquet',
        FORMAT='PARQUET'
    ) AS [nyc];
```

Note the use of "filters" using folders and wildcards from Azure Storage

3. Select the Monitor option in Synapse Studio and select SQL Pools. Select Built-in and see statistics about requests. Click on SQL requests to see a history of SQL queries, details of execution, and query text.

4. Using the SQL front-end server connection, connect using SSMS

5. Notice in Object Explorer it kind of looks like Azure SQL Database

6. Run the following T-SQL queries

```sql
SELECT @@VERSION;
GO
SELECT * FROM sys.objects;
GO
```
7. Run some of the following T-SQL commands to observe what works and doesn't work with this SQL front-end:

```sql
SELECT @@version;
GO
SELECT * FROM sys.databases;
GO
SELECT * FROM sys.objects;
GO
CREATE TABLE mytab (col1 INT);
GO
sp_configure;
GO
```
9. Open a new query window in SSMS and run the following T-SQL query:

```sql
SELECT r.session_id, r.command, r.status, r.wait_type, r.wait_time, r.wait_resource, t.text
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
GO
```

10. Run the following T-SQL in a query window as you did in Synapse Studio:

```sql
SELECT TOP 100000 * FROM
    OPENROWSET(
        BULK 'https://azureopendatastorage.blob.core.windows.net/nyctlc/yellow/puYear=*/puMonth=*/*.parquet',
        FORMAT='PARQUET'
    ) AS [nyc];
```

11. Run the DMV query again and observe the OPENROWSET query and is properties

12. Run this T-SQL query in a new query window to see "request" history:

```sql
SELECT * FROM sys.dm_exec_requests_history
ORDER BY start_time DESC;
```
