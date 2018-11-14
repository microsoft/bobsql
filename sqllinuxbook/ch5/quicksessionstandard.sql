-- Create an XEvent session based on the XEProfiler feature in SSMS to collect connections and queries
--
CREATE EVENT SESSION [QuickSessionStandardToFile] ON SERVER
ADD EVENT sqlserver.attention(
    ACTION(package0.event_sequence,sqlserver.client_app_name,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.nt_username,sqlserver.query_hash,sqlserver.server_principal_name,sqlserver.session_id)
    WHERE ([package0].[equal_boolean]([sqlserver].[is_system],(0)))),
ADD EVENT sqlserver.existing_connection(SET collect_options_text=(1)
    ACTION(package0.event_sequence,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.nt_username,sqlserver.server_principal_name,sqlserver.session_id)),
ADD EVENT sqlserver.login(SET collect_options_text=(1)
    ACTION(package0.event_sequence,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.nt_username,sqlserver.server_principal_name,sqlserver.session_id)),
ADD EVENT sqlserver.logout(
    ACTION(package0.event_sequence,sqlserver.client_app_name,sqlserver.client_pid,sqlserver.nt_username,sqlserver.server_principal_name,sqlserver.session_id)),
ADD EVENT sqlserver.rpc_completed(
    ACTION(package0.event_sequence,sqlserver.client_app_name,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.nt_username,sqlserver.query_hash,sqlserver.server_principal_name,sqlserver.session_id)
    WHERE ([package0].[equal_boolean]([sqlserver].[is_system],(0)))),
ADD EVENT sqlserver.sql_batch_completed(
    ACTION(package0.event_sequence,sqlserver.client_app_name,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.nt_username,sqlserver.query_hash,sqlserver.server_principal_name,sqlserver.session_id)
    WHERE ([package0].[equal_boolean]([sqlserver].[is_system],(0)))),
ADD EVENT sqlserver.sql_batch_starting(
    ACTION(package0.event_sequence,sqlserver.client_app_name,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.nt_username,sqlserver.query_hash,sqlserver.server_principal_name,sqlserver.session_id)
    WHERE ([package0].[equal_boolean]([sqlserver].[is_system],(0))))
ADD TARGET package0.event_file(SET filename=N'QuickSessionStandard.xel',max_file_size=(5),max_rollover_files=(4))
WITH (MAX_MEMORY=8192 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=5 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=PER_CPU,TRACK_CAUSALITY=ON,STARTUP_STATE=OFF)
GO
