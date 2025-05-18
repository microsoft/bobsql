# ABORT_QUERY_EXECUTION query hint in SQL Server 2025

This is a demo for the new ABORT_QUERY_EXECUTION hint in SQL Server 2025. This feature is used to mark a query that may be causing major system performance issues to automatically be aborted on its next and subsequent executions.

## Prerequisites

1. Use the prerequisites in the [SQL Server 2025 Engine Demos](../../readme.md) readme.

2. Download the database AdventureWorks from <https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2022.bak>.

4. Restore the database using the script **restore_adventureworks.sql** (You may need to edit the file paths for the backup and/or database and log files). You can also use the **AdventureWorks.bacpac** file to import data and schema.

5. Enable the query store by executing the script **enablequerystore.sql**. This will enable the query store for the AdventureWorks database.

## References

Find out more about SQL Server 2025 at https://aka.ms/sqlserver2025docs.

## Demo - Using ABORT_QUERY_HINT to cancel a query

In this demonstration you will see how to use the ABORT_QUERY_HINT query hint to cancel the future execution a query. This is useful when you have a query that is causing performance problems and you want to cancel future executions of a query without modifying the application.

1. Load the script **poorquery.sql** in a SSMS query edtior window. Execute the query in the script. This query will take 12-15 seconds to complete. This query is contrived but does represent a query that performs poorly. Microsoft Copilot was used to build this query. The example for this query is based on this scenario. "The company needs to understand which products are performing well, identify high-value customers, and analyze sales patterns over time. The report should include metrics such as average unit price, total sales, order count, and the most recent purchase date for each customer. Additionally, the company wants to see the number of reviews for each product to gauge customer satisfaction.". The query could be absolutely tuned but represents an example where the application cannot be changed or there are lack of controls on what queries users can execute

2. Load the script **findtopdurationqueries.sql** in a SSMS query editor window. Execute the query in the script. This will show you the top queries by duration in the query store. The query at the stop should the query in **poorquery.sql**. Very the **query_sql_text** matches the query in poorquery.sql. Note the **query_id** for the query.

3. Load the script **setabortqueryhint.sql** in a SSMS query editor window. This script will cancel the query in **poorquery.sql**. Replace the **query_id** in the script with the **query_id** from the previous step. Execute the query in the script.

4. Execute the query again in **poorquery.sql**. You will see that the query is cancelled immediately with the following error:

```plaintext
Msg 8778, Level 16, State 1, Line 1
Query execution has been aborted because the ABORT_QUERY_EXECUTION hint was specified
```

5. Optionally you can use the script **clearabortqueryhint.sql** to clear the ABORT_QUERY_HINT for the query. This will allow the query to run normally.