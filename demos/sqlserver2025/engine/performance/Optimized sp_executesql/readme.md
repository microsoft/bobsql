# Optimized sp_executesql in SQL Server 2025

This is a demo for the new optimized sp_executesql in SQL Server 2025. This feature allows you to optimize the performance of sp_executesql by reusing the plan for the statement or batch through preventing multiple copies of the same query plan to be cached. This can reduce memory pressure and improve performance.

This system procedure sp_executesql is used to execute a T-SQL statement or a batch that can be reused multiple times. Drivers can use sp_executesql to execute a parameterized query as seen in this documentation [page](https://learn.microsoft.com/en-us/sql/connect/ado-net/configure-parameters)

## Prerequisites

1. Use the prerequisites in the [SQL Server 2025 Engine Demos](../../readme.md) readme.

2. Download the database AdventureWorks from <https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2022.bak>.

4. Restore the database using the script **restore_adventureworks.sql** (You may need to edit the file paths for the backup and/or database and log files). You can also use the **AdventureWorks.bacpac** file to import data and schema.

5. Install **ostress.exe** from the RML Utilities at https://aka.ms/ostress. Use all the defaults. This demonstration relies on concurrent queries and ostress.exe is used to simulate concurrent queries. This is a Windows only tool so if you have a Linux server you will need to configure the scripts to run ostress.exe to reference the remote server.

6. Edit the script **workload.cmd** if necessary to reference the correct server name and database name. This script will be used to run concurrent queries. The script assumes the default path for ostress.exe, that you are running this on the same server where SQL Server in installed, and used your current account with integrated security. Make any edits you need to reference the corret server and user.

7. **Optional:** You can trace locks that are acquired and released as part of this demonstration using the script **trace_locks.sql** to create an extended event session. This script filters on only user sessions and your user database. Substitute the dbid after you have restored AdventureWorks in all places in the script if necessary (the current script assumes dbid = 5).

## References

Find out more about SQL Server 2025 at https://aka.ms/sqlserver2025docs.

## Demo 1 - Plan cache and locking without optimized sp_executesql

In this demonstration, you will see how the execution of concurrent batches of sp_executesql will result in the same query being cached multiple times. This can lead to memory pressure and reduced performance.

1. Load the script **disable_optimized_sp_executesql** in a SSMS query editor window. This script will disable the optimized sp_executesql feature. Execute the script.

2. Load the script **clearplancache.sql** in a SSMS query editor window. This script will clear the plan cache of the Adventureworks database. Execute the script.

3. Load the script **getcachedplans.sql** in a SSMS query editor window. This script will show you the number of cached plans for the query. You will execute the script after running the workload to see the number of cached plans.

4. Optionally start the extended session from the script **trace_locks.sql** to trace locks acquired and released. In SSMS, you can use the Watch Live Data option to see the events as they occur.

5. From a command line run the script **workload.cmd**. It should complete in less than a second. There is no output from the script.

6. Execute the SQL batch from the script **getcachedplans.sql**. You will see multiple rows returned from the same compiled plan. This is because no compile lock is used on the parameterized query like a stored procedure.

7. If you ran the extended events session, you can observe in the extended events output right after the batch has started there is no OBJECT X lock as you would normally see from a stored procedure.

## Demo 2 - Plan cache and locking with optimized sp_executesql

In this demonstration, you will see how the execution of concurrent batches of sp_executesql will result in the same query being cached only once. This can lead to reduced memory pressure and improved performance.

1. Enable optimized sp_execuesql by loading the script **enable_optimized_sp_executesql.sql** in a SSMS query editor window. Execute the script.

2. Clear the plan cache by executing the script **clearplancache.sql**.

3. Run the script **workload.cmd** from the command line. It should complete in less than a second. There is no output from the script.

4. Observe the plan cache by executing the SQL batch from the script **getcachedplans.sql**. You will see only one row returned from the compiled plan.

5. You can observe in the extended events output right after the batch has started there is an OBJECT X lock. This is because the plan is cached and the query is treated like a stored procedure with optimized sp_executesql enabled.
