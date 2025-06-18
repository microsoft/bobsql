# Demonstration of internals of log records and blocks

Show basics of log records with XEvent and sys.fn_dblog()

1. Start this XEvent session from **tracelogrecs.sql** and click on watch live databse

```sql
CREATE EVENT SESSION [trace_logrecs] ON SERVER 
ADD EVENT sqlserver.transaction_log(
    ACTION(package0.callstack_rva,sqlserver.is_system,sqlserver.session_id)
    WHERE ([database_id]>(5)))
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
GO
```

In the live data window, odd these fields to grid:

Operation
context
session_id
is_system


1. Create a database but make it simple recovery and turn off ODS. Using **1_createdb.sql**.

```sql
DROP DATABASE IF EXISTS simplerecoverydb;
GO
CREATE DATABASE simplerecoverydb;
GO
ALTER DATABASE simplerecoverydb SET RECOVERY SIMPLE;
GO
ALTER DATABASE simplerecoverydb SET QUERY_STORE = OFF;
GO
```

2. Create a table first and then use CHECKPOINT to clear the log using **2_simpletable.sql**

```sql
USE simplerecoverydb;
GO
DROP TABLE IF EXISTS asimpletable;
GO
CREATE TABLE asimpletable (col1 INT);
GO
CHECKPOINT
GO
```

3. Use the script **3_lookatthelog.sql** to look at the log records:

Note: You may need to run checkpoint again to "clear" the log before running this script.

```sql
USE simplerecoverydb;
GO
SELECT * FROM sys.fn_dblog(NULL);
GO
```

3. Now show a basic INSERT on a heap using **4_heapinsert.sql**

Note: Clear the XEvent session first as it may contain diagnostics from other databases.

```sql
USE simplerecoverydb;
GO

-- Run this and show it doesn't generate a logrec
BEGIN TRAN;

-- Show the logrecs

-- Now run an INSERT and COMMIT
INSERT INTO asimpletable VALUES (1);
COMMIT TRAN;

-- Show the logrecs for just an INSERT (implicit COMMIT)
INSERT INTO asimpletable VALUES (1);
GO
```

Walk throught the logrecs. What are all the other log reocrds for? It is for allocation a page and system table updates.

Show columns like Operation, Context, Transaction ID, AllocUnitID, AllocUnitName, PageID, Transaction name, Descriptin (this is generated an not in the log record)

Show the Extended Events output to match it.

So a "user transaction" to start to wrap it but multiple "system transactions" inside it.

4. Run an INSERT again (no COMMIT needed) and see what the logrecs look like. Just 3 logrecs now.

Looking at the logrecs can you tell which log records go into a log block together? The offset of the log record is the offset in the log block (divided by sector size).

You can find a log block physically in a log file by using this formula:

<log block offset>*0x200 (512 bytes)+sys.dm_db_log_info.vlf_begin_offset


```sql

5. Create a table to show updates using **5_create_clustered_table.sql**

```sql
USE simplerecoverydb;
GO
DROP TABLE IF EXISTS asimpleclusteredtable;
GO
CREATE TABLE asimpleclusteredtable (col1 INT primary key clustered, col2 INT);
GO
INSERT into asimpleclusteredtable VALUES (1, 1);
GO
```

6. Update the primary key and look at the logrecs using **6_update_clindex_key.sql**

```sql
USE simplerecoverydb;
GO
CHECKPOINT;
GO
BEGIN TRAN
UPDATE asimpleclusteredtable SET col1 = 10;
COMMIT TRAN;
GO
```

Now show there is A DELETE followed by an INSERT. The RowLog Contents 0 and 1 show the before and after values.

7. Now update the non-key column update as in-place but also roll it back using **7_update_clindex_nonkey.sql**:

```sql
USE simplerecoverydb;
GO
CHECKPOINT;
GO
BEGIN TRAN
UPDATE asimpleclusteredtable SET col2 = 10;
ROLLBACK TRAN;
GO
```

Now example log recs including rowlog contents for before and after images and the COMPENSATION records.

8. What does TRUNCATE TABLE look like?

```sql
USE simplerecoverydb;
GO
CHECKPOINT;
GO
TRUNCATE TABLE asimpletable;
GO
```

9. What about CREATE INDEX? (Bonus. Not shown in presentations typically) using **8_create_big_cl_index.sql**:

```sql
USE simplerecoverydb;
GO
DROP TABLE IF EXISTS bigtab;
GO
CREATE TABLE bigtab (col1 INT, col2 CHAR(7000));
GO
DECLARE @x int;
SET @x = 0;
WHILE (@x < 1000)
BEGIN
	INSERT INTO bigtab VALUES (@x, 'x');
	SET @x = @x + 1;
END
GO
CHECKPOINT;
GO
CREATE UNIQUE CLUSTERED INDEX bigtab_idx ON bigtab (col1);
GO
```
