# Demo for CE Feedback for SQL Server 2022

This is a set of steps to see CE feedback in action and how it can improve query performance with no code changes

## Prereqs

- SQL Server 2022 CTP 2.0 Evaluation Edition
- 4 CPUs (this may still work on less)
- 4 Gb RAM
- Latest build of SQL Server Management Studio 18.X

## Demo Steps

1. Create a directory at c:\sql_sample_databases to store backups and files.
1. Download the AdventureWorks2016_EXT sample backup from https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2016_EXT.bak
1. Restore AdventureWorks_EXT sample backup using restore_adventureworks_ext.sql. Modify the file paths as needed on your system.
1. Run create_xevent_seassion.sql to create and start an Extended Events session to view feedback events. Use SSMS in Object Explorer to view the session with Watch Live Data
1. Add an ncl index on City column for Person.Address using create_index_on_city.sql
1. Set dbcompat to 160 and turn on query store using dbcompat160.sql
1. Run a batch to prime CE feedback using cefeedbackquerybatch.sql
1. Run the query a single time to active CE feedback using cefeedbackquery.sql
1. Run the queries in check_query_hints_and_feedback.sql to see if CE feedback is initiated. You should see a statement of PENDING_VALIDATION from the 2nd DMV query
1. Run the query again in cefeedbackquery.sql
1. Run the queries in check_query_hints_and_feedback.sql again and you will see a query hint has been stored and the status in the 2nd DMV is VERIFICATION_PASSED
1. View the XEvent session data to see how feedback was provided and then veried to be faster 
1. With the hint now in place, run the queries from the batch to match the number of executions usin cefeedbackquerybatch.sql
1. Using Query Store Reports for Top Resource Consuming Queries to compare the query with different plans with and without the hint. The plan with the hint (now using an Index Scan should be overall faster and consume less CPU)

