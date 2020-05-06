# Lightweight Query Profiling

In this example, you will learn how Lightweight Query Profiling can give you performance insights at a deep level anytime, anywhere.

## Requirements

All these examples run with SQL Server 2019 and Azure SQL. These T-SQL scripts can be run with a tool like SSMS.

## Steps

1. Run the query **mysmartsqlquery.sql** in one session. This query should run and take a long time to complete
2. In another session, go through the steps of **show_active_queries.sql** to see the query and its live progress. Find the problem with the query and why it is taking so long.

## Notes

You can read more Lightweight Query Profiling at https://docs.microsoft.com/en-us/sql/relational-databases/performance/query-profiling-infrastructure?view=sql-server-ver15#lwp.