SET NOCOUNT ON;

IF CONVERT(int, SERVERPROPERTY('EngineEdition')) NOT IN (2, 3, 4, 8)
    THROW 51000, 'This kit supports SQL Server and Azure SQL Managed Instance, not Azure SQL Database, Synapse, or Fabric.', 1;
IF CONVERT(int, SERVERPROPERTY('EngineEdition')) <> 8
   AND CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) < 15
    THROW 51000, 'SQL Server 2019 or later is required.', 1;
IF DB_NAME() <> N'tempdb'
    THROW 51000, 'Connect to tempdb before running this script.', 1;

DECLARE @sample_time_utc datetime2(3) = SYSUTCDATETIME();

SELECT @sample_time_utc AS sample_time_utc, v.database_id,
       DB_NAME(v.database_id) AS source_database,
       v.reserved_page_count, v.reserved_space_kb / 1024.0 AS traditional_tempdb_version_store_mb
FROM sys.dm_tran_version_store_space_usage AS v
ORDER BY v.reserved_space_kb DESC, v.database_id;

SELECT @sample_time_utc AS sample_time_utc, d.database_id, d.name AS database_name,
       d.is_read_committed_snapshot_on, d.snapshot_isolation_state_desc,
       d.is_accelerated_database_recovery_on,
       p.persistent_version_store_size_kb / 1024.0 AS off_row_persistent_version_store_mb
FROM sys.databases AS d
LEFT JOIN sys.dm_tran_persistent_version_store_stats AS p ON p.database_id = d.database_id
ORDER BY d.database_id;

SELECT @sample_time_utc AS sample_time_utc,
       a.transaction_id, a.session_id, a.is_snapshot,
       a.elapsed_time_seconds, a.transaction_sequence_num,
       a.first_snapshot_sequence_num,
       s.status AS session_status, s.open_transaction_count,
       r.request_id, DB_NAME(r.database_id) AS request_database,
       r.status AS request_status, r.blocking_session_id, r.wait_type
FROM sys.dm_tran_active_snapshot_database_transactions AS a
LEFT JOIN sys.dm_exec_sessions AS s ON s.session_id = a.session_id
LEFT JOIN sys.dm_exec_requests AS r ON r.session_id = a.session_id
ORDER BY a.elapsed_time_seconds DESC, a.transaction_id, r.request_id;
