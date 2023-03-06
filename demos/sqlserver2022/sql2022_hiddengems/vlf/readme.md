# Demo to show transaction log autogrow improvements in SQL Server 2022

This demo shows new transaction log autogrow improvements in SQL Server 2022

## Show log autogrow behavior in SQL Server 2019

First show the log autogrow behavior in SQL Server 2019

### Setup

- Install SQL Server 2019 (any edition)
- Run the script **xe.sql** to setup an Extended Event session to track log file size changes and wait types that indicate tlog zero writes are occurring. In SSMS, right click on the session and select Watch Live Data.
- Edit the script **createdb.sql** for your file paths. This script is used to create the new db. Pay attention to the initial size and autogrow properties.
- Run the script **clear_wait_types.sql** to clear wait stats.
- Load the script **countvlfs.sql**
- Load the script **wait_types.sql**

### Reproduce log autogrows

- Run the script **ddl.sql**. Notice this takes about 30 seconds.
- Observe in XEvent the different events. You see events for **PREEMPTIVE_OS_WRITEFILE_GATHER** which indicate zeroing files. This is for the CREATE DATABASE statement and expected.
- Now notice a pattern where you see **database_file_size_changed** events for the transaction log combined with **PREEMPTIVE_OS_WRITEFILEGATHER** events. This shows that any log grow requires a write operation to zero out the log file growth.
- Run the query in **wait_types.sql**. Notice the total wait time for **PREEMPTIVE_OS_WRITEFILEGATHER** which is about 20 seconds. So our workload was delayed for 20 seconds trying to zero log growths.
- Run the query in **countvlfs.sql**. Notice there are some 50 virtual log file rows.

### Observe the performance impact on recovery

- Use Task Manager to kill SQLSERVR.EXE
- Restart the SQL Server service
- After about 30 seconds look at the ERRORLOG
- You will see an entry that looks like this

`Recovery completed for database testvlf (database ID 5) in 33 second(s) (analysis 4765 ms, redo 27350 ms, undo 76 ms [system undo 0 ms, regular undo 0 ms].) This is an informational message only. No user action is required`

The analysis number of almost 5 seconds is due to the number of VLFs in the log

## Show log autogrow enhancements for SQL Server 2022

Show log autogrow enhancements for SQL Server 2022

### Setup

- InstalL SQL Server 2022 (any edition)
- Run the script **xe.sql** to setup an Extended Event session to track log file size changes and wait types that indicate tlog zero writes are occurring. In SSMS, right click on the session and select Watch Live Data.
- Run the script clear_wait_types.sql to clear wait stats.
- Load the script **countvlfs.sql**
- Load the script **wait_types.sql**

### Reproduce log autogrow

- Run the script **ddl.sql**. Notice this takes only a few seconds (it took ~30 seconds on SQL Server 2019)
- Observe in XEvent the different events. You see events for **PREEMPTIVE_OS_WRITEFILEGATHER** which indicate zeroing files. This is for the CREATE DATABASE statement and expected.
- Now notice a pattern where you see **database_file_size_changed** events but NO **PREEMPTIVE_OS_WRITEFILEGATHER** events which means we are not zeroing the log file with each autogrow
- Run the query in **wait_types.sql**. Notice there are only a few waits on **PREEMPTIVE_OS_WRITEFILEGATHER**.
- Run the query in **countvlfs.sql**. Notice there are now only ~20 VLFs (a 50% reduction from SQL Server 2019)

### Observe the performance impact on recovery

- Use Task Manager to kill SQLSERVR.EXE
- Restart the SQL Server service
- After about 5 seconds look at the ERRORLOG file
- You will see an entry that looks like this

`Recovery completed for database testvlf (database ID 10) in 4 second(s) (analysis 1104 ms, redo 2186 ms, undo 9 ms [system undo 0 ms, regular undo 0 ms].) ADR-enabled=0, Is primary=1, OL-Enabled=0. This is an informational message only. No user action is required.`

Notice the Analysis phase goes down from 5 seconds to 1 second.