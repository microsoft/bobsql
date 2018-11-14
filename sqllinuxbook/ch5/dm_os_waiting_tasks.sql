-- Show all user requests that are waiting on a resource
--
SELECT wt.session_id, wt.wait_type, wt.wait_duration_ms
FROM sys.dm_os_waiting_tasks wt
INNER JOIN sys.dm_exec_sessions es
ON es.session_id = wt.session_id
AND es.is_user_process = 1
GO