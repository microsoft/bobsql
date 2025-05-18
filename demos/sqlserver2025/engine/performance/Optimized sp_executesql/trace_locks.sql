CREATE EVENT SESSION [tracing_sp_executesql] ON SERVER 
ADD EVENT sqlserver.lock_acquired(
    ACTION(sqlserver.session_id)
    WHERE ([package0].[equal_uint64]([database_id],(5)) AND [sqlserver].[is_system]=(0))),
ADD EVENT sqlserver.lock_released(
    ACTION(sqlserver.session_id)
    WHERE ([package0].[equal_uint64]([database_id],(5)) AND [sqlserver].[is_system]=(0))),
ADD EVENT sqlserver.sql_batch_completed(
    ACTION(sqlserver.session_id)
    WHERE ([package0].[equal_uint64]([sqlserver].[database_id],(5)) AND [sqlserver].[is_system]=(0))),
ADD EVENT sqlserver.sql_batch_starting(
    ACTION(sqlserver.session_id)
    WHERE ([package0].[equal_uint64]([sqlserver].[database_id],(5)) AND [sqlserver].[is_system]=(0)))
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
GO