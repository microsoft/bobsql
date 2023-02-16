SELECT * FROM sys.dm_os_wait_stats
WHERE waiting_tasks_count > 0
AND wait_type like 'PREEMPTIVE%'
ORDER BY wait_time_ms desc
GO

