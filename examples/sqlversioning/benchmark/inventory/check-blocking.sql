-- Check for active blocking
SET NOCOUNT ON;
SELECT 
    r.session_id AS blocked_spid,
    r.blocking_session_id AS blocking_spid,
    r.wait_type,
    r.wait_time AS wait_ms,
    r.wait_resource,
    DB_NAME(r.database_id) AS db_name,
    SUBSTRING(t.text, 1, 80) AS blocked_query
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id > 0
  AND r.database_id = DB_ID('inventory_baseline')
ORDER BY r.wait_time DESC;
GO
SELECT 
    wait_type,
    COUNT(*) AS blocked_count,
    SUM(wait_time) AS total_wait_ms,
    AVG(wait_time) AS avg_wait_ms
FROM sys.dm_exec_requests
WHERE blocking_session_id > 0
  AND database_id = DB_ID('inventory_baseline')
GROUP BY wait_type;
