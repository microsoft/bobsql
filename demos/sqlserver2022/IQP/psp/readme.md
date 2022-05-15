# Parameter Sensitive Plan Optimization (PSP) in SQL Server 2022

Here are the steps to demonstrate the new PSP optimization feature for SQL Server 2022

## Prerequisites

- VM with at least 4 CPUs and 24 Gb RAM
- SQL Server 2022 CTP 2.0
- SQL Server Management Studio (SSMS) Version 19 Preview
- Download ostress.exe from https://www.microsoft.com/en-us/download/details.aspx?id=103126

Follow these steps to demonstrate Parameter Sensitive Plan (PSP) optimization

## Setup the demo

1. Copy WideWorldImporters from https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Full.bak (the restore script assumes c:\sql_sample_databases)
2. Restore the WideWorldImporters backup. You can edit and use the **restorewwi.sql** script.
3. Load and execute the **populatedata.sql** script to load more data into the Warehouse.StockItems table. This script will take 5 mins to run
4. Rebuild an index associated with the table with **rebuild_index.sql**
5. Create a new procedure to be used for the workload test using **proc.sql**.
6. Edit your servername in sqlsetup.cmd and execute the script. This will ensure the WideWorldImporters database is at dbcompat 150 and clear the query store.

## See a PSP problem for a single query execution.

7. Set the actual execution plan option in SSMS. Run query_plan_seek.sql in a query window in SSMS. Note the query time is fast and the values from SET STATISTICS TIME is around 20ms. Note the query plan uses an Index Seek.
8. In a different query window set the actual execution option in SSMS. Run query_plan_scan.sql in a query windows in SSMS. Note the query plan uses an Clustered Index Scan and parallelism.
9. Now go back and run query_plan_seek.sql again. Note the timing from SET STATISTICS IO is now ~250ms. Ten times slower but a single execution seems fast.

## See a workload problem for PSP

10. Setup perfmon to catpure % processor time and batch requests/second
11. Edit the scripts workload_index_scan.cmd and workload_index_seek.cmd for your servername.
12. Put ostress.exe in your path or copy it to the local directory. It is installed by default in C:\Program Files\Microsoft Corporation\RMLUtils
13. Run workload_index_seek.cmd. This should complete in a few seconds. Observe perfmon counters.
14. Run workload_index_scan.cmd. This should take longer but now locks into cache a plan for a scan.
15. Run workload_index_seek.cmd again. Observe perfmon counters. Notice much higher CPU and much lower batch requests/sec. 
16. Hit <Ctrl>+<C> in the command window for workload_index_seek.cmd as it can take minutes to complete.
17. Use the query suppliercount.sql to see the skew in supplierID values in the table. This explains why "one size does not fit all" for the stored procedure based on parameter values.

## Solve the problem in SQL Server 2022

17. Let's get this workload much faster using PSP optimization. Execute the T-SQL script **dbcompat160.sql** with SSMS.
18. Run workload_index_seek.cmd again. Should finish in a few seconds.
19. Run workload_index_scan.cmd again.
20. Run workload_index_seek.cmd again and see that it now finishs again in a few seconds. Observe perfmon counters and see consistent performance.
21. Run Top Resource Consuming Queries report and see that there are two plans for the same stored procedure
22. It looks like are "two" queries but these are two query "variants". Use the script query_store_dmvs.sql to see the details.