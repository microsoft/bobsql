CREATE EVENT SESSION [trace_ag_log_block] ON SERVER 
ADD EVENT sqlserver.hadr_capture_log_block(
    ACTION(package0.callstack_rva,sqlserver.session_id)),
ADD EVENT sqlserver.hadr_db_commit_mgr_harden(
    ACTION(package0.callstack_rva,sqlserver.session_id)),
ADD EVENT sqlserver.hadr_db_commit_mgr_update_harden(
    ACTION(package0.callstack_rva,sqlserver.session_id)),
ADD EVENT sqlserver.hadr_log_block_group_commit(
    ACTION(package0.callstack_rva,sqlserver.session_id)),
ADD EVENT sqlserver.hadr_log_block_send_complete(
    ACTION(package0.callstack_rva,sqlserver.session_id)),
ADD EVENT sqlserver.hadr_receive_harden_lsn_message(
    ACTION(package0.callstack_rva,sqlserver.session_id)),
ADD EVENT sqlserver.log_block_pushed_to_logpool(
    ACTION(package0.callstack_rva,sqlserver.session_id)),
ADD EVENT sqlserver.log_flush_complete(
    ACTION(package0.callstack_rva,sqlserver.session_id)),
ADD EVENT sqlserver.log_flush_start(
    ACTION(package0.callstack_rva,sqlserver.session_id)),
ADD EVENT sqlserver.recovery_unit_harden_log_timestamps(
    ACTION(package0.callstack_rva,package0.collect_current_thread_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlos.worker_address,sqlserver.is_system,sqlserver.request_id,sqlserver.session_id,sqlserver.sql_text)),
ADD EVENT sqlserver.sql_batch_completed(SET collect_batch_text=(1)
    ACTION(sqlserver.session_id))
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
GO


