SELECT scheduler_id, cpu_id, status, is_online, current_tasks_count, current_workers_count, active_workers_count, work_queue_count
FROM sys.dm_os_schedulers
GO