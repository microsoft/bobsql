SET NOCOUNT ON;

IF CONVERT(int, SERVERPROPERTY('EngineEdition')) NOT IN (2, 3, 4, 8)
    THROW 51000, 'This kit supports SQL Server and Azure SQL Managed Instance, not Azure SQL Database, Synapse, or Fabric.', 1;
IF CONVERT(int, SERVERPROPERTY('EngineEdition')) <> 8
   AND CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) < 15
    THROW 51000, 'SQL Server 2019 or later is required.', 1;
IF DB_NAME() <> N'tempdb'
    THROW 51000, 'Connect to tempdb before running this script.', 1;

DECLARE @sample_time_utc datetime2(3) = SYSUTCDATETIME();
DECLARE @include_sql_text bit = 0;

-- Session counters cover completed tasks; active task counters are separate.
;WITH active_tasks AS
(
    SELECT session_id,
           SUM(user_objects_alloc_page_count - user_objects_dealloc_page_count) AS user_pages,
           SUM(internal_objects_alloc_page_count - internal_objects_dealloc_page_count) AS internal_pages
    FROM sys.dm_db_task_space_usage
    GROUP BY session_id
)
SELECT @sample_time_utc AS sample_time_utc,
       s.session_id, s.status, s.open_transaction_count,
       CONVERT(decimal(19, 2),
           (su.user_objects_alloc_page_count - su.user_objects_dealloc_page_count
            + COALESCE(t.user_pages, 0)) / 128.0) AS user_objects_net_mb,
       CONVERT(decimal(19, 2),
           (su.internal_objects_alloc_page_count - su.internal_objects_dealloc_page_count
            + COALESCE(t.internal_pages, 0)) / 128.0) AS internal_objects_net_mb,
       CONVERT(decimal(19, 2),
           su.user_objects_deferred_dealloc_page_count / 128.0) AS deferred_user_deallocation_mb
FROM sys.dm_db_session_space_usage AS su
JOIN sys.dm_exec_sessions AS s ON s.session_id = su.session_id
LEFT JOIN active_tasks AS t ON t.session_id = su.session_id
WHERE s.session_id <> @@SPID
ORDER BY su.user_objects_alloc_page_count - su.user_objects_dealloc_page_count
         + su.internal_objects_alloc_page_count - su.internal_objects_dealloc_page_count
         + COALESCE(t.user_pages, 0) + COALESCE(t.internal_pages, 0) DESC, s.session_id;

;WITH request_tasks AS
(
    SELECT session_id, request_id,
           SUM(user_objects_alloc_page_count - user_objects_dealloc_page_count) AS user_pages,
           SUM(internal_objects_alloc_page_count - internal_objects_dealloc_page_count) AS internal_pages
    FROM sys.dm_db_task_space_usage
    GROUP BY session_id, request_id
)
SELECT @sample_time_utc AS sample_time_utc,
       r.session_id, r.request_id, DB_NAME(r.database_id) AS request_database,
       r.status, r.command, r.blocking_session_id, r.wait_type, r.wait_time AS wait_time_ms,
       r.wait_resource, r.cpu_time AS cpu_time_ms, r.total_elapsed_time AS elapsed_time_ms,
       r.reads, r.writes, r.logical_reads, r.row_count,
       r.granted_query_memory AS granted_query_memory_pages,
       CONVERT(decimal(19, 2), COALESCE(t.user_pages, 0) / 128.0) AS active_task_user_net_mb,
       CONVERT(decimal(19, 2), COALESCE(t.internal_pages, 0) / 128.0) AS active_task_internal_net_mb
FROM sys.dm_exec_requests AS r
LEFT JOIN request_tasks AS t
    ON t.session_id = r.session_id AND t.request_id = r.request_id
WHERE r.session_id <> @@SPID
ORDER BY COALESCE(t.user_pages, 0) + COALESCE(t.internal_pages, 0) DESC, r.session_id, r.request_id;

-- Query text can contain credentials or business data; opt in only for private capture.
IF @include_sql_text = 1
BEGIN
    SELECT @sample_time_utc AS sample_time_utc, r.session_id, r.request_id,
           SUBSTRING(txt.text, r.statement_start_offset / 2 + 1,
               (CASE WHEN r.statement_end_offset = -1 THEN DATALENGTH(txt.text)
                     ELSE r.statement_end_offset END - r.statement_start_offset) / 2 + 1) AS statement_text
    FROM sys.dm_exec_requests AS r
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS txt
    WHERE r.session_id <> @@SPID;
END;
