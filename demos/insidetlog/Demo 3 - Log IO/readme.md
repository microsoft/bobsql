# Demo for Log I/O

## Show log flushes

1. Show which sessions are Log Writers with this query

SELECT * FROM sys.dm_exec_requests
WHERE COMMAND = 'LOG WRITER';
GO

1. Use this XEvent script to start an XEvent session

CREATE EVENT SESSION [trace_log_io] ON SERVER 
ADD EVENT sqlserver.databases_log_flush(
    ACTION(package0.callstack_rva,sqlserver.database_name,sqlserver.is_system,sqlserver.session_id,sqlserver.sql_text)
    WHERE ([database_id]<>(1))),
ADD EVENT sqlserver.databases_log_flush_wait(
    ACTION(package0.callstack_rva,sqlserver.database_name)
    WHERE ([database_id]<>(1))),
ADD EVENT sqlserver.log_flush_complete(
    ACTION(package0.callstack_rva,sqlserver.is_system,sqlserver.session_id)),
ADD EVENT sqlserver.log_flush_requested(
    ACTION(package0.callstack_rva,sqlserver.is_system,sqlserver.session_id)),
ADD EVENT sqlserver.log_flush_start(
    ACTION(package0.callstack_rva,sqlserver.database_id,sqlserver.is_system,sqlserver.session_id)
    WHERE ([package0].[greater_than_uint64]([database_id],(5)))),
ADD EVENT sqlserver.sql_batch_completed(SET collect_batch_text=(1)
    ACTION(sqlserver.database_id,sqlserver.database_name,sqlserver.session_id)
    WHERE ([sqlserver].[database_id]<>(1))),
ADD EVENT sqlserver.sql_batch_starting(
    ACTION(sqlserver.database_id,sqlserver.database_name,sqlserver.session_id)
    WHERE ([sqlserver].[database_id]<>(1)))
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
GO

Now run various scenarios to look at log flushing:

1. In a database where delayed durability is NOT ON

CREATE TABLE t (col1 int);
GO
BEGIN TRAN
INSERT INTO t VALUES (1);
GO

Now look at the event live data. Note: if you see a flush use the SQLCallStackResolver to see what it is. You will notice this is related to QDS

Now do a COMMIT TRAN and look at the event live data. You will see a flush related to the commit. Notice the session is is from the Log Writers

Show the callstacks for the databases_log_flush and databases_log_flush_wait events with SQLCallStackResolver

1. In a database where delayed durability is ON

CREATE TABLE bigtab (col1 int, col2 char(7000) not null);
GO

use a larger table
show the same sequence
Keep adding inserts until you see a flush which happens because we filled a log buffer

But notice there is no databases_log_flush_wait event.

1. Show the same for a transaction with tempdb

Show inline log writing. Enable lock pages and now see if log flushes happen inline. They only happen when the log buffer is full.

## Show how log flushing works from a log block perspective

Use the following XEvent session

CREATE EVENT SESSION [trace_log_io_bytes] ON SERVER 
ADD EVENT sqlserver.file_write_completed(
    ACTION(package0.callstack_rva,sqlserver.is_system,sqlserver.session_id)
    WHERE ([package0].[greater_than_uint64]([database_id],(5)) AND [file_id]=(2))),
ADD EVENT sqlserver.sql_batch_completed(SET collect_batch_text=(1)
    ACTION(sqlserver.database_id)
    WHERE ([sqlserver].[database_id]>(5))),
ADD EVENT sqlserver.transaction_log(SET collect_database_name=(1)
    ACTION(package0.callstack_rva,sqlserver.is_system,sqlserver.session_id)
    WHERE ([database_id]>(5)))
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
GO

Now run the following scenarios:

Use the db with delayed OFF

Run various transactions to show the size of log records but the writes are all sector size aligned. Show the offset and look at VLFs so you can see where they land