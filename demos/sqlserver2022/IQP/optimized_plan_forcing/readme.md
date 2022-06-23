# Demo for Optimized Plan Forcing in SQL Server 2022

This is a demonstration of how optimized plan forcing can reduce compilation time for queries that have had plans forced in the Query Store

## Prerequisites

- Install SQL Server 2022
- VM or Server with 4 CPUs and 4Gb RAM
- A tool to run SQL queries like SQL Server Management Studio (latest 18.X or 19.X build) or Azure Data Studio (latest build)

## Demo Steps

1. Create a directory called **c:\sql_sample_databases**
2. Copy the WideWorldImporters full backup from https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Full.bak to **c:\sql_sample_databases**.
3. Execute the script **restorewwwi.sql** to restore the WideWorldImporters database. Note here we can keep the current dbcompat setting of 130 and still take advantage of optimized plan forcing.
4. Execute the script **bigjoin.sql**. This will take ~4-8 seconds to complete (your mileage could vary).
5. Take note in the Messages result from SET STATISTICS TIME the "SQL Server parse and compile time" compared to the SQL Server Execution Times CPU time. Notice it can be as much as 30-40% of the CPU time. This means the compilation of the query took a significant amount of CPU time for the overall query execution.
6. Run the script **find_query_in_query_store.sql** to find the plan_id and query_id for the recent query. Notice the column **has_compile_replay_script** has a value = 1. This means this query is a candidate for optimized plan forcing. Take note of the numbers for compile duration.
7. Edit the script **forceplan.sql** to put in the correct values for the @query_id and @plan_id parameter values. Execute the stored procedure in the script.
8. Run the script **bigjoin.sql** again. Notice the significant reduction in SQL Server parse and compile time from the initial execution as a % of CPU time for the query. It can drop down as low as 2-3%.
1. We want to ensure we have the latest persisted data in QDS so execute the script **flush_query_store.sql**.
1. Run the script **find_query_in_query_store.sql** again. Take note that the last compile time reflects the new time and the average has gone down. Since the query has only been run once the average doesn't accurately reflect what will happen in the future with every compilation now using optimized plan forcing.