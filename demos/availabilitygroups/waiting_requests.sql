SELECT er.request_id, er.command, er.wait_type, er.last_wait_type, er.wait_time
FROM sys.dm_exec_requests er
JOIN sys.dm_exec_sessions es
ON er.session_id = es.session_id
AND es.is_user_process = 1;
GO