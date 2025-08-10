SELECT 
    blocking_session_id AS BlockingSessionID,
    session_id AS BlockedSessionID,
    wait_type,
    wait_time,
    wait_resource,
    DB_NAME(database_id) AS DatabaseName,
    TEXT AS BlockingQuery
FROM 
    sys.dm_exec_requests
CROSS APPLY 
    sys.dm_exec_sql_text(sql_handle)
WHERE 
    blocking_session_id <> 0
ORDER BY 
    BlockingSessionID, BlockedSessionID;
GO
