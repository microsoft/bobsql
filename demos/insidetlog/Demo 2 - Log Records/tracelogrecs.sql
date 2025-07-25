CREATE EVENT SESSION [trace_logrecs] ON SERVER 
ADD EVENT sqlserver.transaction_log(
    ACTION(package0.callstack_rva,sqlserver.is_system,sqlserver.session_id)
    WHERE ([database_id]>(5)))
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
GO