USE MASTER;
GO
IF EXISTS (SELECT * FROM sys.dm_xe_sessions WHERE name = 'query_abort_xe')
BEGIN
DROP EVENT SESSION [query_abort_xe] ON SERVER;
END
GO
CREATE EVENT SESSION [query_abort_xe] ON SERVER 
ADD EVENT sqlserver.attention(
    ACTION(package0.callstack_rva,sqlserver.session_id,sqlserver.sql_text)),
ADD EVENT sqlserver.query_abort(SET collect_input_buffer=(1),collect_task_callstack_rva=(1),collect_worker_wait_stats=(1)
    ACTION(package0.callstack_rva,sqlserver.session_id))
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
GO
ALTER EVENT SESSION query_abort_xe
ON SERVER
STATE = START;
GO
