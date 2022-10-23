# Demo for Memory Grant Feedback Persistence in SQL Server 2022

The following is a demonstration of memory grant feedback persistence in SQL Server 2022

## Prerequisites

- SQL Server 2022 Evaluation Edition
- Virtual machine or computer with minimum 2 CPUs with 8Gb RAM.
- SQL Server Management Studio (SSMS). The latest 18.x build or 19.x build will work

## Demo steps

1. Download the **WideWorldImportersDW** database backup from https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImportersDW-Full.bak.
2. Restore this database to your SQL Server 2022 instance. You can use the provided **restorewwidw.sql** script. You may need to change the directory paths for the location of your backup and where you will restore the database files.
3. In order to run some of the examples, you will need larger tables than what is installed by default in WideWorldImportersDW. Therefore, run the script **extendwwidw.sql** to create a larger table.
4. Setup the demo by executing the script **setup.sql**
5. Simulate statistics out of date by executing the script **set_stats.sql**.
6. Using SSMS choose the button to see Include Actual Execution plan and execute a query that will use a memory grant from **execute_query.sql**. The query will take about 30 seconds to complete.
7. Select the Execution Plan in the results. You will see a graphical showplan. Notice the yellow warning on the hash join operator. If you hover over this operator with the cursor you will see a warning about a spill to tempdb. Notice the spill involves writing out ~400Mb of pages to tempdb. You can also see the estimated number of rows is far lower than the actual number of rows. 
8. Hover over the SELECT operator and notice the memory grant is 1.4Mb which is far short of the ~400Mb spilled to tempdb. Right click the SELECT operator and select Properties. Expand the MemoryGrantInfo option. Notice the **IsMemoryGrantFeedbackAdjusted** = NoFirstExecution. This means no adjustment has been made since there is no feedback and they query was just compiled. The "used" memory is only the memory used as part of the grant and does not account for the spill.
9. Now execute **get_plan_feedback.sql** and notice the output. You will see that feedback has been stored to allocate a significant larger memory grant on next query execution.
10. Run **execute_query.sql** again
11. This time the query runs in seconds. Notice there is no spill warning for the hash join. Hovering over the SELECT operator will show a significantly larger grant. Right clicking on the SELECT operator and selecting properties will show in the MemoryGrantInfo section **IsMemoryGrantFeedbackAdjusted = YesAdjusting**.  
12. Run **get_plan_feedback.sql** again and see the last_query_memory_kb reflect the new larger memory grant.
13. Execute the script **clear_proc_cache.sql**. This will clear the plan cache. Prior to SQL Se****rver 2022, this would have "lost" the memory grant feedback.
14. Run **execute_query.sql** again. You will see the grant is still using the feedback now in the query store and runs in a few seconds.