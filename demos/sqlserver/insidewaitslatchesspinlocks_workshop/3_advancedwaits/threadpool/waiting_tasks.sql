SELECT wt.session_id, wait_duration_ms, wait_type, blocking_session_id, t.task_address, t.worker_address
FROM sys.dm_os_waiting_tasks wt
JOIN sys.dm_os_tasks t
ON wt.waiting_task_address = t.task_address;
GO