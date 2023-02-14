# Demo to detect an antipattern query with Extended Events in SQL Server 2022

This is a demo to show how to detect an antipattern query using Extended Events in SQL Server 2022

## Setup

1. Execute the script xe.sql
2. Execute the script customer_ddl.sql. Notice there is an index on customer_id.
3. Using SSMS right click on the Extended Events session and select Watch Live Data

## Reproduce the problem

4. Run the script repro.sql

## Analyze the problem and find a solution

5. In the Watch Live Data window you can see the type of antipattern which is an index cannot be used.
6. Copy the plan handle and paste into get_query_plan.sql and execute the query.
7. Click on the XML plan value. See the plan doesn't use an index. Hover over SELECT and see the warning which shows a convert is causing the index not to be used.
8. Show customer_proc_fix.sql as one way to fix this.