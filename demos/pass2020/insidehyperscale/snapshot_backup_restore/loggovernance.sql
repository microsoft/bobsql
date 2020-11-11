SELECT * FROM sys.dm_db_resource_stats
GO
SELECT name, delta_log_bytes_used/(1024*1024) as log_used_mb, snapshot_time FROM 
sys.dm_resource_governor_resource_pools_history_ex
WHERE delta_log_bytes_used > 0
and name = 'SloSharedPool1'
ORDER BY snapshot_time desc
GO
SELECT * FROM sys.dm_os_wait_stats
WHERE wait_type like '%RATE%'
ORDER BY waiting_tasks_count DESC
GO
