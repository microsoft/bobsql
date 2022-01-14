# Demo steps for Parameter Sensitive Plan Optimization (PSP)

Here are the steps to demonstrate the new PSP optimization feature for SQL Server 2022

## Setup

1. Copy WideWorldImporters from https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Full.bak

2. Install SQL Server 2022 (during private preview I used developer edition)

3. Restore the WideWorldImporters backup. You can edit and use the **restorewwi.sql** script.

4. Load and execute the **populatedata.sql** script to load more data into the Warehouse.StockItems table

5. Rebuild an index associated with the table with **rebuild_index.sql**

6. Create a new procedure to be used for the workload test using **proc.sql**.

7. Edit your servername in sqlsetup.cmd and execute the script. This will ensure the WideWorldImporters database is at dbcompat 150, clear the query store, and set any trace flags needed during private preview.]

8. Edit the scripts workload_index_scan.cmd and workload_index_seek.cmd for your servername.

## Show query plan differences for PSP

1. Using SSMS turn on the Actual Execution Plan option and execute the query in **query_plan_seek.sql**. You will see this executes very fast and uses an Index Seek.

2. In a different query window, using SSMS turn on the Actual Execution Plan option and execute the query in **query_plan_scan.sql**. You will this takes several seconds to run and uses an Index Scan. This script clears procedure cache for the database to simulate plan cache eviction.

3. Run the query in **query_plan_seek.sql** again. You will see it now uses a scan but doesn't seem to run that much slower.

3. Now to see PSP optimization in action, run the script **dbcompat160.sql** to set the dbcompat level to 160. This enables the QP to use PSP optimization.

4. Now repeat the same steps as 1-3 above. When you execute the query in **query_plan_seek.sq**l the 2nd time it should now use an index seek.

5. You can observe different plans for the same query_hash using the scripts **dmv_query_stats.sql** and**query_store_dmvs.sql**.

## Show performance differences using a workload

Even though in the previous section the performance of an individual execution of a query didn't seem to regress because of PSP, what if the query in query_plan_index.sql had to be run my multiple users frequently? This is where having the right plan matters.

Note: if you want to observe the performance differences in perfmon, add counters for batch requests/sec and % Processor time.

1. Run **sqlsetup.cmd as you did in the setup section.**. This wil reset the dbcompat level and clear the query store.

2. Run **workload_index_seek.cmd**. This runs the stored procedure with the same parameter as seen with query_plan_seek.sql Not the overall duration time from ostress. Also if you have setup perfmon, note the high, but reasonable CPU time and the avg batch requests/sec.

3. Run **workload_index_scan.cmd**. This will clear procedure cache to simulate a plan cache eviction and run the same query as in query_plan_scan.sql.

4. Now run **workload_index_seek.cmd** again. You will see quickly it runs past the last duration time. If you look at perfmon you will see almost 100% CPU time with huge drop in batch requests/sec. This is because all the users are running the proc with index scans. You will need to cancel this workload by hitting <Ctrl>+<C> as it can take many minutes to finish.

5. Let's get this workload much faster using PSP optimization. Execute the T-SQL script **dbcompat160.sql** with SSMS.

6. Run through the same sequence as in steps 2-4. You will see now in Step 4 the execution of workload_index_seek.cmd should be the same as the first run and perfmon should show consistent execution.

7. You can observe the same details for query plans using **dmv_query_stats.sql** and **query_store_dmvs.sql**.
