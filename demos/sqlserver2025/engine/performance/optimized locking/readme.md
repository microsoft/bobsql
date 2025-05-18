# Optimized locking SQL Server 2025

This is a demo for the optimized locking feature in SQL Server 2025. This feature is designed to improve the performance of concurrent transactions by reducing contention on locks.

## Prerequisites

1. Use the prerequisites in the [SQL Server 2025 Engine Demos](../readme.md) readme.

2. Download the database AdventureWorks from <https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2022.bak>.

4. Restore the database using the script **restore_adventureworks.sql** (You may need to edit the file paths for the backup and/or database and log files). You can also use the **AdventureWorks.bacpac** file to import data and schema.

5. Enable Accelerated Database Recovery for the database AdventureWorks using the script **enableadr.sql**.

6. Make sure optimized locking is disabled by executing the script **disableoptimizedlocking.sql**.

## References

Find out more about SQL Server 2025 at https://aka.ms/sqlserver2025docs.

## Demo 1 - Lock Escalation

In this demonstration you will see how optimized locking can avoid scenarios that typically require lock escalation and can affect the concurrency and availability of applications. In this scenario, the application needs to update a large number of rows with at T-SQL UPDATE statement on the table Sales.SalesOrderHeader. The developer of the application has been seeing blocking problems with this update and Adminstrators have seen excessive lock memory required.

### Show Lock Escalation without optimized locking

1. Load the script **getlocks.sql** in a SSMS query edtior window. You will use this script to observe locking behavior.

2. Load the script **updatefreightsmall.sql** in a SSMS query editor window.  

This script will increase the freight costs for each order by 1 for the first 2500 rows. Execute the first batch in the query script up to the ```GO``` statement. Do not execute the ```ROLLBACK TRAN``` statement.

3. Switch to the query editor window for **getlocks.sql** and look at the results

You will see ~2500 KEY X locks and 111 PAGE locks. Without optimized locking, key and page locks are held as long as the transaaction is active. If more rows are updated, lock escalation can occur. Move forward to the next steps to see how.

First execute the ```ROLLBACK TRAN``` statement in the **updatefreightsmall.sql** script. This will release all locks and allow the next step to proceed.

4. Observe lock escalation by loading the script **updatefreightbig.sql** in a SSMS query editor window

This script will increase the freight costs for each order by 1 for the first 10000 rows. Execute the first batch in the query script up to the ```GO``` statement. Do not execute the ```ROLLBACK TRAN``` statement.

5. Switch to the query editor window for **getlocks.sql** and look at the results

You will see that lock escalation has occurred. You will now only see an OBJECT X lock. This is because the number of locks has exceeded the threshold for lock escalation.

6. You can see this harms concurrency. Load the script **updatefreightmax.sql** in a SSMS query editor window.

This script updates the freight for a row not affected by the previous update. Execute the first batch in the query script up to the ```GO``` statement. Do not execute the ```ROLLBACK TRAN``` statement. Notice this batch does not complete. This is because the update is blocked by the OBJECT X lock.

7. Load the script **showblocking.sql** in a SSMS query editor window. This script will show you the blocking problem.

8. Rollback the transactions in **updatefreightbig.sql** and **updatefreightmax.sql**. You can do this by executing the ```ROLLBACK TRAN``` statement in those scripts. Leave all query editor windows open for the next steps.

### Show Lock Escalation with optimized locking

1. Enable optimized locking by loading and executing the script **enableoptimizedlocking.sql** in a SSMS query editor window. This will enable optimized locking for the database AdventureWorks.

2. Execute the first batch in the query editor window for **updatefreightsmall.sql** up to the ```GO``` statement. Do not execute the ```ROLLBACK TRAN``` statement.

3. Switch to the query editor window for **getlocks.sql** and look at the results.

You will see an OBJECT IX lock as seen before but now only a XACT X lock. This is because the transaction ID lock is held for the duration of the transaction. KEY and PAGE locks are released as soon as each row is updated. This allows for more concurrency.

4. Rollback the transaction in **updatefreightsmall.sql** by executing the ```ROLLBACK TRAN``` statement.

5. To see how lock escalation is avoided, execute the batch in **updatefreightbig.sql** up to the ```GO``` statement. Do not execute the ```ROLLBACK TRAN``` statement.

6. Check the locks in the **getlocks.sql** query editor window. You will see an OBJECT IX lock and a XACT X lock. There is no lock escalation.

7. Execute the first batch in **updatefreightmax.sql** up to the ```GO``` statement. Do not execute the ```ROLLBACK TRAN``` statement. Notice this batch is not blocked.

8. Rollback the transactions in **updatefreightbig.sql** and **updatefreightmax.sql**. You can do this by executing the ```ROLLBACK TRAN``` statement in those scripts.

9. For the next demo you can close all query editor windows for scripts **except for getlocks.sql and showblocking.sql**

## Demo 2 - Lock After Qualification (LAQ) with optimized locking

Lock after qualification (LAQ) is an optimization that evaluates query predicates using the latest committed version of the row without acquiring a lock, thus improving concurrency.

LAQ requires both optimized locking AND read committed snapshot isolation (RCSI) to be enabled. Without optimized locking and RCSI, DML statements can require update and exclusive locks when qualifying rows from the query criteria. If optimized locking is enabled but not RCSI, qualificatoin is still required for TID (XACT) locks. However, if RCSI is also enabled, this qualification is not required. This demonstration will show you the benefits of LAQ.

Let's look at a scenario for the AdventureWorks database where LAQ can improve the concurrency of the application. In this scenario, the application needs to execute an update for specific PurchaseOrderNumbers in the Sales.SalesOrderHeader. Developers have seen blocking problems with this update. This column does not have an index currently so an update for a specific row can require a scan of the clustered index. This table is not large so the scan can be fast and so an index was not created. Developers and adminstrators are looking for ways to avoid the blocking problem.

### Blocking for updates without LAQ

Let's see what the blocking problem looks like without LAQ. Remember to have the **getlocks.sql** and **showblocking.sql** scripts loaded in query editor windows in SSMS.

1. The AdventureWorks sample database has RCSI enabled by default so run the script **disablercsi.sql** to disable RCSI.

2. Load the **updatefreightpo1.sql** script in a SSMS query editor window. This script will update the freight for a specific PurchaseOrderNumber. Execute the first batch in the query script up to the ```GO``` statement. Do not execute the ```ROLLBACK TRAN``` statement.

3. Load the **updatefreightpo2.sql** script in a SSMS query editor window. This script will update the freight for a different specific PurchaseOrderNumber. Execute the first batch in the query script up to the ```GO``` statement. Do not execute the ```ROLLBACK TRAN``` statement. Notice this batch is blocked.

4. Run the query in the **showblocking.sql** query editor window. You will see that the second update is blocked by the first update. The waiting resource is an XACT resource. Run the query in the **getlocks.sql** query editor window to see the locks being held and attempted. Notice the second update is requesting and waiting for a Shared (S) XACT lock on the same row that the first update has locked.

5. Rollback the transaction in **updatefreightpo1.sql** by executing the ```ROLLBACK TRAN``` statement. Then rollback the transaction in **updatefreightpo2.sql** by executing the ```ROLLBACK TRAN``` statement.

Leave all query editor windows open for the next steps.

### Blocking for updates with LAQ

1. Enable RCSI by executing the script **enablercsi.sql** in a SSMS query editor window.

2. Execute the query in the **updatefreightpo1.sql** script in a SSMS query editor window. Execute the first batch in the query script up to the ```GO``` statement. Do not execute the ```ROLLBACK TRAN``` statement.

3. Execute the query in the **updatefreightpo2.sql** script in a SSMS query editor window. Execute the first batch in the query script up to the ```GO``` statement. Do not execute the ```ROLLBACK TRAN``` statement. Notice this batch is not blocked.

4. Execute the query in **getlocks.sql** query editor window to see the locks being held and attempted. Notice that both sessions now have Exclusive (X) XACT locks. This is because LAQ allows the second update to qualify rows that don't meet the query criteria without acquiring a lock.