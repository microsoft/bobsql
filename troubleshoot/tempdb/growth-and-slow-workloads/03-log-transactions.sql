SET NOCOUNT ON;

IF CONVERT(int, SERVERPROPERTY('EngineEdition')) NOT IN (2, 3, 4, 8)
    THROW 51000, 'This kit supports SQL Server and Azure SQL Managed Instance, not Azure SQL Database, Synapse, or Fabric.', 1;
IF CONVERT(int, SERVERPROPERTY('EngineEdition')) <> 8
   AND CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) < 15
    THROW 51000, 'SQL Server 2019 or later is required.', 1;
IF DB_NAME() <> N'tempdb'
    THROW 51000, 'Connect to tempdb before running this script.', 1;

DECLARE @sample_time_utc datetime2(3) = SYSUTCDATETIME();

SELECT @sample_time_utc AS sample_time_utc,
       d.log_reuse_wait_desc,
       l.total_log_size_in_bytes / 1048576.0 AS total_log_mb,
       l.used_log_space_in_bytes / 1048576.0 AS used_log_mb,
       l.used_log_space_in_percent
FROM sys.databases AS d
CROSS JOIN sys.dm_db_log_space_usage AS l
WHERE d.database_id = DB_ID();

SELECT @sample_time_utc AS sample_time_utc, dt.transaction_id,
       dt.database_transaction_begin_time AS database_transaction_begin_time_server_local,
       DATEDIFF_BIG(SECOND, dt.database_transaction_begin_time, SYSDATETIME()) AS transaction_age_seconds,
       dt.database_transaction_type, dt.database_transaction_state,
       dt.database_transaction_log_record_count,
       dt.database_transaction_log_bytes_used / 1048576.0 AS log_used_mb,
       dt.database_transaction_log_bytes_reserved / 1048576.0 AS log_reserved_mb
FROM sys.dm_tran_database_transactions AS dt
WHERE dt.database_id = DB_ID()
ORDER BY dt.database_transaction_begin_time, dt.transaction_id;

-- Separate owner mappings avoid multiplying transaction totals by sessions or requests.
SELECT @sample_time_utc AS sample_time_utc,
       dt.transaction_id, st.session_id, st.is_user_transaction,
       s.status AS session_status, s.open_transaction_count,
       r.request_id, r.status AS request_status, r.command,
       r.blocking_session_id, r.wait_type, r.wait_time AS wait_time_ms
FROM sys.dm_tran_database_transactions AS dt
LEFT JOIN sys.dm_tran_session_transactions AS st ON st.transaction_id = dt.transaction_id
LEFT JOIN sys.dm_exec_sessions AS s ON s.session_id = st.session_id
LEFT JOIN sys.dm_exec_requests AS r ON r.session_id = st.session_id
WHERE dt.database_id = DB_ID()
ORDER BY dt.transaction_id, st.session_id, r.request_id;
