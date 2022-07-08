# Demo for CE Feedback for SQL Server 2022

This is a set of steps to see CE feedback in action and how it can improve query performance with no code changes

## Prereqs

- VM or computer with at min 2 CPUs and 8Gb RAM.

**Note**: Some of the timings from this exercise may differ if you use a VM or computer with more resources than the minimum.
 
- SQL Server 2022 CTP 2.0
- SQL Server Management Studio (SSMS) Version 19 Preview

## Demo Steps

1. Create a directory called **c:\sql_sample_databases** to store backups and files.
1. Download the AdventureWorks2016_EXT sample backup from  https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2016_EXT.bak and copy it into the c:\sql_sample_databases folder.
1. Restore AdventureWorks_EXT sample backup using **restore_adventureworks_ext.sql**.
1. Run **create_xevent_seassion.sql** to create and start an Extended Events session to view feedback events. Use SSMS in Object Explorer to view the session with Watch Live Data.
1. Add an ncl index on City column for Person.Address using the script **create_index_on_city.sql**.
1. Set dbcompat to 160 and turn on query store using the script **dbcompat160.sql**.
1. Run a batch to prime CE feedback using the script **cefeedbackquerybatch.sql**.
1. Run the query a single time to active CE feedback using **cefeedbackquery.sql**.
1. Run the queries in the script **check_query_hints_and_feedback.sql** to see if CE feedback is initiated. You should see a statement of PENDING_VALIDATION from the 2nd DMV query.
1. Run the query again in the script **cefeedbackquery.sql**.
1. Run the queries in the script **check_query_hints_and_feedback.sql** again and you will see a query hint has been stored and the status in the 2nd DMV is VERIFICATION_PASSED.
1. View the XEvent session data to see how feedback was provided and then verified to be faster. The query_feedback_validation event shows the feedback_validation_cpu_time is less than original_cpu_time.
1. With the hint now in place, run the queries from the batch to match the number of executions using the script **cefeedbackquerybatch.sql**.
1. Using Query Store Reports for Top Resource Consuming Queries to compare the query with different plans with and without the hint. The plan with the hint (now using an Index Scan should be overall faster and consume less CPU). This includes Total and Avg Duration and CPU.