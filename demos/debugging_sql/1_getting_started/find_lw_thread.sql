SELECT er.session_id, th.os_thread_id
FROM sys.dm_exec_requests er
JOIN sys.dm_os_tasks t
ON t.session_id = er.session_id
AND er.command = 'LAZY WRITER'
JOIN sys.dm_os_workers w
ON w.task_address = t.task_address
JOIN sys.dm_os_threads th
ON th.worker_address = w.worker_address;
GO

-- Now take the result and use ~~[os_thread_id in hex]k

