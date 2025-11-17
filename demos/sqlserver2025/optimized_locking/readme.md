# Optimized Locking in SQL Server 2025

This demo demonstrates optimized locking in SQL Server 2025, which improves concurrency by avoiding lock escalation and reducing lock memory overhead through transaction ID locking.

## Prerequisites

- **SQL Server 2025 Developer Edition** - [Download here](https://www.microsoft.com/en-us/sql-server/sql-server-downloads)
- **AdventureWorks Database** - [Download AdventureWorks2022.bak](https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2022.bak)
- **SQL Server Management Studio (SSMS) 21** - [Download here](https://aka.ms/ssms21)

## Overview

Optimized locking is a significant enhancement in SQL Server 2025 that addresses two major concurrency challenges:

1. **Lock Escalation** - Traditionally, updating many rows causes SQL Server to escalate from row/page locks to table locks, blocking other queries
2. **Lock Memory Overhead** - Each row and page lock consumes memory, limiting scalability

**How Optimized Locking Works:**
- Uses transaction ID (TID) locks instead of traditional row/page locks
- Only the TID lock is logged in the transaction log
- Dramatically reduces redo work on secondary replicas (AG, log shipping)
- Avoids lock escalation scenarios
- Improves concurrency for large updates

## Files

| File | Purpose |
|------|---------|
| `00_a_restore_adventureworks.sql` | Restores the AdventureWorks sample database |
| `00_b_enableadr.sql` | Enables Accelerated Database Recovery (required) |
| `00_c_disableoptimizedlocking.sql` | Disables optimized locking for comparison |
| `01_getlocks.sql` | Query to observe current locks in the database |
| `02_updatefreightsmall.sql` | Updates 2500 rows to show traditional locking |
| `03_updatefreightbig.sql` | Updates 10000 rows to demonstrate lock escalation |
| `04_updatefreightmax.sql` | Concurrent update to show blocking from escalation |
| `05_showblocking.sql` | Displays blocking sessions |
| `06_enableoptimizedlocking.sql` | Enables optimized locking feature |
| `07_disablercsi.sql` | Disables RCSI (for TID lock demonstration) |
| `08_updatefreightpo1.sql` | First concurrent update with optimized locking |
| `09_updatefreightpo2.sql` | Second concurrent update with optimized locking |
| `10_enablercsi.sql` | Re-enables RCSI |

## Step-by-Step Instructions

## Demo 1: Lock Escalation Without Optimized Locking

This demonstration shows how traditional locking causes lock escalation and blocking issues.

### Step 1: Setup Environment
```sql
-- Run: 00_a_restore_adventureworks.sql
```

Restores the AdventureWorks database. Edit file paths as needed for your environment.

```sql
-- Run: 00_b_enableadr.sql
```

Enables Accelerated Database Recovery, which is required for optimized locking.

```sql
-- Run: 00_c_disableoptimizedlocking.sql
```

Ensures optimized locking is disabled so you can see traditional behavior first.

### Step 2: Observe Traditional Locking Behavior

Open `01_getlocks.sql` in one SSMS query window. You'll use this throughout the demo to observe locking behavior.

```sql
-- Open in separate window: 01_getlocks.sql
```

This query shows:
- Lock types (KEY, PAGE, OBJECT)
- Lock modes (S, X, U, etc.)
- Lock counts
- Resource descriptions

### Step 3: Update Small Number of Rows
```sql
-- Run: 02_updatefreightsmall.sql
```

This script updates the first 2500 rows in `Sales.SalesOrderHeader`, increasing freight costs by 10%.

**Execute only the first batch** up to the `GO` statement. Do NOT execute `ROLLBACK TRAN` yet.

### Step 4: Examine Locks for Small Update

Switch to the `01_getlocks.sql` window and execute it.

**Expected Results:**
- ~2500 KEY (X) locks - one per row updated
- ~111 PAGE locks
- Lock memory is consumed for each lock
- Transaction holds all these locks until commit/rollback

This demonstrates traditional row-level locking behavior.

**Now rollback:** Switch back to `02_updatefreightsmall.sql` and execute the `ROLLBACK TRAN` statement.

### Step 5: Demonstrate Lock Escalation
```sql
-- Run: 03_updatefreightbig.sql
```

This script updates 10,000 rows - enough to trigger lock escalation.

**Execute only the first batch** up to the `GO` statement. Do NOT execute `ROLLBACK TRAN` yet.

### Step 6: Observe Lock Escalation

Switch to `01_getlocks.sql` and execute it.

**Expected Results:**
- Only ONE OBJECT (X) lock - the table is now locked!
- No individual KEY or PAGE locks visible
- Lock escalation occurred to reduce lock memory overhead

This is the problem: the entire table is now locked, blocking all other queries.

### Step 7: Demonstrate Blocking from Escalation

Keep the transaction from Step 5 open. Now open another window:

```sql
-- In new window, run: 04_updatefreightmax.sql
```

This script attempts to update a SINGLE ROW that was NOT affected by the previous update.

**Execute only the first batch** up to the `GO` statement.

**Expected Result:** The query hangs! It cannot complete because the table is locked by the other transaction.

### Step 8: Confirm Blocking
```sql
-- In another window, run: 05_showblocking.sql
```

This shows the blocking session and what it's waiting on.

**Cleanup:** 
- Rollback the transaction in `03_updatefreightbig.sql`
- This will unblock and complete the transaction in `04_updatefreightmax.sql`
- Rollback that transaction too

## Demo 2: Optimized Locking Eliminates Lock Escalation

Now see how optimized locking solves these problems.

### Step 9: Enable Optimized Locking
```sql
-- Run: 06_enableoptimizedlocking.sql
```

Enables the optimized locking feature at the database level.

### Step 10: Disable RCSI (Optional but Recommended)
```sql
-- Run: 07_disablercsi.sql
```

Disables Read Committed Snapshot Isolation to better demonstrate TID locking behavior. With RCSI enabled, readers don't acquire locks anyway, so disabling it makes the demo clearer.

### Step 11: Large Update with Optimized Locking

Open two SSMS query windows side by side.

**Window 1:**
```sql
-- Run: 08_updatefreightpo1.sql
```

This updates freight for orders with odd-numbered purchase order numbers.

**Execute only the first batch** up to the `GO` statement. Leave the transaction open.

### Step 12: Check Locks with Optimized Locking

In your `01_getlocks.sql` window, execute the query.

**Expected Results:**
- Very few locks visible!
- No thousands of KEY locks
- No lock escalation
- Uses TID (Transaction ID) locking instead

### Step 13: Concurrent Update - No Blocking!

While Window 1's transaction is still open:

**Window 2:**
```sql
-- Run: 09_updatefreightpo2.sql
```

This updates freight for orders with even-numbered purchase order numbers.

**Execute only the first batch** up to the `GO` statement.

**Expected Result:** This query completes immediately! No blocking occurs even though both transactions are updating the same table with thousands of rows.

Check locks again with `01_getlocks.sql` - you'll see both transactions' locks coexist without escalation.

**Key Point:** With optimized locking:
- No lock escalation to table level
- Concurrent updates on same table succeed
- Improved concurrency and throughput
- Reduced lock memory consumption

**Cleanup:**
- Rollback both transactions (`08_updatefreightpo1.sql` and `09_updatefreightpo2.sql`)

### Step 14: Re-enable RCSI (Optional)
```sql
-- Run: 10_enablercsi.sql
```

Re-enables Read Committed Snapshot Isolation if you disabled it earlier.

## What You'll Learn

- How traditional locking leads to lock escalation
- Impact of lock escalation on concurrency and blocking
- How optimized locking uses TID locks instead of row/page locks
- Benefits of reduced lock memory and redo overhead
- Improved concurrency for large batch updates
- When and how to enable optimized locking

## Key Concepts

**Lock Escalation:** SQL Server's mechanism to reduce lock memory by converting many fine-grained locks (row/page) to fewer coarse-grained locks (table), which reduces concurrency.

**Transaction ID (TID) Locking:** Optimized locking approach where only the transaction ID lock is maintained, avoiding individual row and page locks.

**Accelerated Database Recovery (ADR):** Required prerequisite for optimized locking; provides fast recovery and enables transaction-level locking.

**Lock Memory:** Memory consumed by the lock manager; each lock requires memory, limiting scalability for large updates.

**Redo Overhead:** Work required on secondary replicas (Availability Groups, log shipping) to replay transaction log; reduced with optimized locking since only TID locks are logged.

## Benefits of Optimized Locking

✅ **Eliminates Lock Escalation** - No more table locks from large updates  
✅ **Improved Concurrency** - Multiple large updates can run simultaneously  
✅ **Reduced Lock Memory** - Dramatically less memory consumed by locks  
✅ **Better Secondary Replica Performance** - Less redo work on AG secondaries  
✅ **Higher Throughput** - More queries can execute concurrently  
✅ **Fewer Blocking Issues** - Applications experience less contention  

## Use Cases

**Batch Processing:**
- Large ETL operations
- Bulk data updates
- Nightly maintenance jobs
- Data warehouse loads

**High-Concurrency Applications:**
- SaaS applications with many concurrent users
- E-commerce platforms
- Financial systems
- Multi-tenant applications

**Availability Groups:**
- Reduce redo latency on secondary replicas
- Improve secondary replica read performance
- Better replica synchronization

**Large Tables:**
- Updates affecting thousands/millions of rows
- Maintenance operations on large tables
- Index rebuilds and maintenance

## Performance Considerations

**When Optimized Locking Helps Most:**
- Large batch updates (thousands+ rows)
- High concurrency workloads
- Availability Group environments
- Lock escalation issues in current workload

**Requirements:**
- Accelerated Database Recovery must be enabled
- Database compatibility level 160 (SQL Server 2025)
- Works best with READ COMMITTED isolation level

**Limitations:**
- Test thoroughly before production use
- Some specific scenarios may not benefit
- Monitor performance after enabling

## Monitoring Optimized Locking

**Check if Enabled:**
```sql
SELECT name, is_optimized_locking_on
FROM sys.databases
WHERE name = 'AdventureWorks';
```

**Monitor Lock Behavior:**
```sql
SELECT 
    request_session_id,
    resource_type,
    resource_description,
    request_mode,
    request_status
FROM sys.dm_tran_locks
WHERE resource_database_id = DB_ID('AdventureWorks');
```

**Extended Events:**
Monitor lock escalation events to confirm they're eliminated:
```sql
CREATE EVENT SESSION [TrackLockEscalation] ON SERVER
ADD EVENT sqlserver.lock_escalation
ADD TARGET package0.event_file(SET filename=N'LockEscalation.xel')
WITH (MAX_MEMORY=4096 KB);
GO
ALTER EVENT SESSION [TrackLockEscalation] ON SERVER STATE = START;
```

## Best Practices

1. **Test Thoroughly** - Validate in non-production first
2. **Enable ADR First** - Required prerequisite
3. **Monitor Performance** - Compare before/after metrics
4. **Check Secondary Replicas** - Verify redo improvements in AG scenarios
5. **Update Statistics** - Ensure query plans are optimal
6. **Document Changes** - Track when/why optimized locking was enabled
7. **Start with Test Workloads** - Enable for specific databases initially

## Troubleshooting

**Optimized Locking Not Working:**
- Verify ADR is enabled: `SELECT is_accelerated_database_recovery_on FROM sys.databases`
- Check database compatibility level: Must be 160+
- Confirm feature is enabled: `SELECT is_optimized_locking_on FROM sys.databases`
- Restart connections after enabling

**Performance Not Improved:**
- May not benefit small updates (< 1000 rows)
- Check if lock escalation was actually a problem
- Review query plans for other issues
- Monitor wait stats for actual bottlenecks

**Unexpected Behavior:**
- Review isolation level settings
- Check for application-level locking hints
- Verify ADR is functioning correctly
- Check SQL Server error logs for messages

## Comparison: Before and After

| Aspect | Traditional Locking | Optimized Locking |
|--------|-------------------|-------------------|
| **Lock Count** | Thousands of locks | Minimal locks |
| **Lock Memory** | High (MBs) | Low (KBs) |
| **Lock Escalation** | Occurs frequently | Eliminated |
| **Concurrency** | Blocked by escalation | High concurrency |
| **Redo Overhead** | All locks logged | Only TID logged |
| **Blocking** | Common with large updates | Rare |

## Next Steps

- Enable optimized locking in test environments
- Measure performance improvements
- Test with your workload patterns
- Roll out to production gradually
- Monitor and document benefits
- Consider enabling for all databases with concurrency issues
- Combine with other SQL Server 2025 features for maximum performance
