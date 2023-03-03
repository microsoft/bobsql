SELECT er.session_id, er.status, command, blocking_session_id, wait_type, wait_time, wait_resource
FROM sys.dm_exec_requests er
JOIN sys.dm_exec_sessions es
ON er.session_id = es.session_id
AND es.is_user_process = 1;
GO

