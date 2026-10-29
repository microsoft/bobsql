/* Structured snapshot consumed by run-demo.ps1 and build-growth-report.ps1. */
SET NOCOUNT ON;

DECLARE @SnapshotName NVARCHAR(20) = N'$(SnapshotName)';

SELECT CONCAT(
    N'META|', @SnapshotName, N'|',
    CONVERT(NVARCHAR(33), SYSUTCDATETIME(), 126), N'Z|',
    DB_NAME(), N'|',
    CONVERT(NVARCHAR(128), DATABASEPROPERTYEX(DB_NAME(), 'ServiceObjective')), N'|',
    CAST(SUM(reserved_page_count) * 8.0 / 1024 / 1024 AS DECIMAL(18, 3)), N'|',
    CAST((SELECT SUM(size) * 8.0 / 1024 / 1024
          FROM sys.database_files
          WHERE type = 0) AS DECIMAL(18, 3)))
FROM sys.dm_db_partition_stats;

SELECT CONCAT(
    N'TABLE|', @SnapshotName, N'|',
    SCHEMA_NAME(t.schema_id), N'.', t.name, N'|',
    SUM(CASE WHEN p.index_id IN (0, 1) THEN p.row_count ELSE 0 END), N'|',
    CAST(SUM(p.reserved_page_count) * 8.0 / 1024 / 1024 AS DECIMAL(18, 3)))
FROM sys.tables AS t
JOIN sys.dm_db_partition_stats AS p
    ON p.object_id = t.object_id
WHERE t.name IN (N'Observation', N'LabResult', N'ClinicalNote')
GROUP BY t.schema_id, t.name
ORDER BY SCHEMA_NAME(t.schema_id), t.name;

SELECT CONCAT(
    N'IO|', @SnapshotName, N'|Log|',
    COALESCE(SUM(num_of_reads), 0), N'|',
    COALESCE(SUM(num_of_bytes_read), 0), N'|',
    COALESCE(SUM(io_stall_read_ms), 0), N'|',
    COALESCE(SUM(num_of_writes), 0), N'|',
    COALESCE(SUM(num_of_bytes_written), 0), N'|',
    COALESCE(SUM(io_stall_write_ms), 0))
FROM sys.dm_io_virtual_file_stats(DB_ID(), 2);

SELECT CONCAT(
    N'WAIT|', @SnapshotName, N'|', wait_type, N'|',
    waiting_tasks_count, N'|', wait_time_ms, N'|', signal_wait_time_ms)
FROM sys.dm_db_wait_stats
WHERE wait_type = N'WRITELOG'
   OR wait_type = N'LOGBUFFER'
   OR wait_type = N'LOGMGR_FLUSH'
   OR wait_type LIKE N'RBIO_RG[_]%'
   OR wait_type LIKE N'PAGELATCH[_]%'
   OR wait_type LIKE N'PAGEIOLATCH[_]%'
ORDER BY wait_type;

SELECT CONCAT(
    N'RESOURCE|', @SnapshotName, N'|',
    CONVERT(NVARCHAR(33), end_time, 126), N'Z|',
    CAST(avg_cpu_percent AS DECIMAL(9, 3)), N'|',
    CAST(avg_data_io_percent AS DECIMAL(9, 3)), N'|',
    CAST(avg_log_write_percent AS DECIMAL(9, 3)), N'|',
    CAST(max_worker_percent AS DECIMAL(9, 3)), N'|',
    CAST(max_session_percent AS DECIMAL(9, 3)))
FROM sys.dm_db_resource_stats
WHERE end_time >= DATEADD(HOUR, -1, SYSUTCDATETIME())
ORDER BY end_time;
GO