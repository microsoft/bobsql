# Tempdb space resource governance

This is a demo for the tempdb resource governor feature in SQL Server 2025. This feature is designed to help you manage the space used by tempdb by configuring the Resource Governor to limit the space used by tempdb for users both for explicit temporary tables or internal space used for operations like sorts.

## Prerequisites

1. Use the prerequisites in the [SQL Server 2025 Engine Demos](../../readme.md) readme.

## References

Find out more about tempdb space resource governance at https://learn.microsoft.com/sql/relational-databases/resource-governor/tempdb-space-resource-governance

## Scenario

Consider a scenario where you as an administrator struggle to manage the growth of the size of tempdb due to users that may not be aware of the impact of their queries on tempdb. This can lead to performance issues and contention in tempdb.
To address this, you can use the tempdb space resource governance feature to limit the space used by tempdb for users both for explicit temporary tables or internal space used for operations like sorts.

## Setup

Follow these steps connected a sysadmin login.

1. Set the tempdb size

In this scenario you want to establish the default size of tempdb to be 512MB across 8 tempdb data files and a 100MB tempdb log file. You can do this by executing the script **settempdbsize.sql** in a SSMS query editor window. This will set the size of tempdb to 512MB across 8 data files and a 100MB log file.

You decide to leave autogrow for tempdb files to avoid any downtime situations but your goal is to make sure growth does not exceed 512MB because you have carefully planned the usage of tempdb through temporary tables from your developers.

Execut the script **checktempdbsize.sql** in a SSMS query editor window to verify the size of tempdb. You should see that the size of tempdb is 512MB across 8 data files and a 100MB log file.

2. Create a user database to show unexpected tempdb growth

Load and execut the script **createbigdata.sql** in a SSMS query editor window.


1. 
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