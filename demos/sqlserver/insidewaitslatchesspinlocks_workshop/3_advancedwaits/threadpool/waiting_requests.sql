SELECT er.session_id, er.request_id, wait_time, wait_type, wait_resource, blocking_session_id
FROM sys.dm_exec_requests er
JOIN sys.dm_exec_sessions es
ON er.session_id = es.session_id
WHERE es.is_user_process = 1
GO