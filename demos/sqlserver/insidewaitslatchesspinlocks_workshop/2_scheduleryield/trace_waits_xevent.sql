-- How do I know the wait_type = 123?
--
select * from sys.dm_xe_map_values where name = 'wait_types'
and map_value = 'SOS_SCHEDULER_YIELD'
go
CREATE EVENT SESSION [tracing_waits] ON SERVER 
ADD EVENT sqlos.wait_completed(
    ACTION(sqlserver.session_id,sqlserver.sql_text)
    WHERE ([package0].[equal_boolean]([sqlserver].[is_system],(0)) AND [wait_type]=(99)))
ADD TARGET package0.ring_buffer
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
GO