This demo requires the following:

-- A backup of the WideWorldImporters sample database
-- SQL Server 2019 CTP 2.0
-- SQL Server client tools (sqlcmd)
-- SQL Server Management Studio (for Query Store Reports)
-- Windows Performance Monitor
-- RML Utilities (ostress)

1. Restore the WideWorldImporters (Full) database backup

2. Run setup_repro.cmd to create the procedure

3. Use performance monitor to track Processor/%Processor Time and Process/sqlservr/%Processor Time

4. Run repro130.cmd - This should take about 25-30 seconds. Observe processor time in perfmon

5. Run repro150.cmd - This should take about 9 seconds. Observe processor time in perfmon

6. Bring up the Query Store - Top Resource Consuming Queries report. Notice the same query has two plans ands hows a massive performance difference. Notice the Average Duration is 4 secs for the slow query vs 180ms for the fast query.
Show the plans and how the estimates used to be 1 but are not accurate leading to a better join choice

7. Find the query_id from the report

8. Bring up query_plan_diff.sql in SSMS. Substitute in your query_id and see the difference between queries and db compat level. Notice the avg duration and avg logical reads are extremely higher for the plan with dbcompat = 130