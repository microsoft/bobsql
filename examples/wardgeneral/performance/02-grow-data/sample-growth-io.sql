/* Lightweight timeline sample consumed by run-demo.ps1. */
SET NOCOUNT ON;

DECLARE @SampleName NVARCHAR(30) = N'$(SampleName)';
DECLARE @CapturedAtUtc DATETIME2(3) = SYSUTCDATETIME();

SELECT CONCAT(
    N'SAMPLE|', @SampleName, N'|',
    CONVERT(NVARCHAR(33), @CapturedAtUtc, 126), N'Z|',
    CAST(SUM(reserved_page_count) * 8.0 / 1024 / 1024 AS DECIMAL(18, 3)), N'|',
    CAST((SELECT SUM(size) * 8.0 / 1024 / 1024
          FROM sys.database_files
          WHERE type = 0) AS DECIMAL(18, 3)))
FROM sys.dm_db_partition_stats;

SELECT CONCAT(
    N'RESOURCE|', @SampleName, N'|',
    CONVERT(NVARCHAR(33), end_time, 126), N'Z|',
    CAST(avg_cpu_percent AS DECIMAL(9, 3)), N'|',
    CAST(avg_data_io_percent AS DECIMAL(9, 3)), N'|',
    CAST(avg_log_write_percent AS DECIMAL(9, 3)), N'|',
    CAST(max_worker_percent AS DECIMAL(9, 3)), N'|',
    CAST(max_session_percent AS DECIMAL(9, 3)))
FROM
(
    SELECT TOP (1)
        end_time,
        avg_cpu_percent,
        avg_data_io_percent,
        avg_log_write_percent,
        max_worker_percent,
        max_session_percent
    FROM sys.dm_db_resource_stats
    ORDER BY end_time DESC
) AS latest;

SELECT CONCAT(
    N'IO|', @SampleName, N'|Log|',
    COALESCE(SUM(num_of_reads), 0), N'|',
    COALESCE(SUM(num_of_bytes_read), 0), N'|',
    COALESCE(SUM(io_stall_read_ms), 0), N'|',
    COALESCE(SUM(num_of_writes), 0), N'|',
    COALESCE(SUM(num_of_bytes_written), 0), N'|',
    COALESCE(SUM(io_stall_write_ms), 0))
FROM sys.dm_io_virtual_file_stats(DB_ID(), 2);

SELECT CONCAT(
    N'WAIT|', @SampleName, N'|', wait_type, N'|',
    waiting_tasks_count, N'|', wait_time_ms, N'|', signal_wait_time_ms)
FROM sys.dm_db_wait_stats
WHERE wait_type = N'WRITELOG'
   OR wait_type = N'LOGBUFFER'
   OR wait_type = N'LOGMGR_FLUSH'
   OR wait_type LIKE N'RBIO_RG[_]%'
   OR wait_type LIKE N'PAGELATCH[_]%'
   OR wait_type LIKE N'PAGEIOLATCH[_]%'
ORDER BY wait_type;
GO