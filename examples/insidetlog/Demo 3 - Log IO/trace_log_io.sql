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