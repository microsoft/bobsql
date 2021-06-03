-- What is our limit?
SELECT primary_max_log_rate/(1024*1024) as primary_max_log_rate_mb, slo_name, cpu_limit FROM sys.dm_user_db_resource_governance
GO
-- Clear wait stats
dbcc sqlperf("sys.dm_os_wait_stats" , CLEAR)
go
-- Run the workload and see if there are waits
SELECT er.session_id, ew.exec_context_id, er.status, er.command, ew.wait_type, ew.wait_duration_ms
FROM sys.dm_exec_requests er
INNER JOIN sys.dm_exec_sessions es
ON er.session_id = es.session_id
INNER JOIN sys.dm_os_waiting_tasks ew
ON er.session_id = ew.session_id
AND es.is_user_process = 1
AND ew.wait_type like '%RATE%';
GO
-- Have we hit our limit?
SELECT avg_log_write_percent FROM sys.dm_db_resource_stats
GO
-- How much have we used compared to the limit?
SELECT name, delta_log_bytes_used/(1024*1024) as log_used_mb, 
delta_log_bytes_used/(1024*1024)/(duration_ms/1000) as log_rate_mbps, 
duration_ms, snapshot_time 
FROM sys.dm_resource_governor_workload_groups_history_ex
WHERE delta_log_bytes_used > 0
AND name like 'UserPrimaryGroup%'
ORDER BY snapshot_time desc
GO
-- Cumulative log governance waits
SELECT * FROM sys.dm_os_wait_stats
WHERE wait_type like '%RATE%' --or wait_type like '%RBIO%'
ORDER BY waiting_tasks_count DESC
GO
-- Track bytes governed since startup
SELECT * FROM sys.dm_os_performance_counters where counter_name = 'Log Governor Used'
and instance_name not in ('msdb', 'master', 'tempdb', 'model_masterdb', 'model_userdb', 'model', 'mssqlsystemresource', '_Total')
GO
