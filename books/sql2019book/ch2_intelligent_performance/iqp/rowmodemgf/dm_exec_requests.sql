SELECT er.session_id, er.command, er.status, er.wait_type, er.wait_resource, er.wait_time
FROM sys.dm_exec_requests er
JOIN sys.dm_exec_sessions es
ON er.session_id = es.session_id
AND es.is_user_process = 1
GO