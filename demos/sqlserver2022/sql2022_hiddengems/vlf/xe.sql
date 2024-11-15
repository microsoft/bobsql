CREATE EVENT SESSION [track_log_autogrow] ON SERVER 
ADD EVENT sqlos.wait_info_external(
    ACTION(sqlserver.session_id,sqlserver.sql_text)
    WHERE ([wait_type]='PREEMPTIVE_OS_WRITEFILEGATHER')),
ADD EVENT sqlserver.database_file_size_change(
    ACTION(sqlserver.sql_text))
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
GO
ALTER EVENT SESSION [track_log_autogrow] ON SERVER STATE=START;
GO