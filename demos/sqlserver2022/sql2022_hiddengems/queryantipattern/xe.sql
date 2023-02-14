USE MASTER;
GO
IF EXISTS (SELECT * FROM sys.dm_xe_sessions WHERE name = 'query_antipattern_xe')
BEGIN
DROP EVENT SESSION [query_antipattern_xe] ON SERVER;
END
GO
CREATE EVENT SESSION [query_antipattern_xe] ON SERVER 
ADD EVENT sqlserver.query_antipattern(
    ACTION(sqlserver.client_app_name,sqlserver.plan_handle,sqlserver.query_hash,sqlserver.query_plan_hash,sqlserver.sql_text)
    WHERE ([sqlserver].[database_name]=N'query_antipattern'))
ADD TARGET package0.ring_buffer(SET max_memory=(500))
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
GO
ALTER EVENT SESSION query_antipattern_xe
ON SERVER
STATE = START;
GO