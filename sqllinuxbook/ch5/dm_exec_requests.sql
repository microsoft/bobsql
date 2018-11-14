-- Get the session_id, status (RUNNING or SUSPENDED), command (what query), wait_type (if waiting what resource?), and wait_time (how long waiting) for active user requests
--
SELECT er.[session_id], er.[status], er.[command], er.[wait_type], er.[wait_time]
FROM sys.dm_exec_requests er
INNER JOIN sys.dm_exec_sessions es
ON es.[session_id] = er.[session_id]
AND es.[is_user_process] = 1
GO