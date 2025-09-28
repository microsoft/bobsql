-- Current resource usage & size snapshot for the *current* database
-- Returns last 15s-sample percentages + allocated/used sizes + log usage + file I/O summary

WITH res AS (
    SELECT TOP (1)
        end_time,
        avg_cpu_percent,
        avg_data_io_percent,
        avg_log_write_percent,
        avg_memory_usage_percent,
        max_worker_percent,
        max_session_percent
    FROM sys.dm_db_resource_stats              -- last ~1 hour, 15s granularity
    ORDER BY end_time DESC
),
data_files AS (
    -- Allocated sizes from file metadata (8 KB pages)
    SELECT
        SUM(CASE WHEN type_desc = 'ROWS' THEN size END) * 8.0 / 1024 AS data_allocated_mb,
        SUM(CASE WHEN type_desc = 'LOG'  THEN size END) * 8.0 / 1024 AS log_file_allocated_mb,
        SUM(size) * 8.0 / 1024                               AS total_allocated_mb
    FROM sys.database_files
),
data_used AS (
    -- Used space estimate from partition stats (excludes free space in data files)
    SELECT
        SUM(used_page_count) * 8.0 / 1024 AS data_used_mb,
        SUM(reserved_page_count) * 8.0 / 1024 AS data_reserved_mb
    FROM sys.dm_db_partition_stats
),
logstats AS (
    -- Transaction log size and usage (MB) and current holdup reason (if any)
    SELECT
        total_log_size_mb,
        active_log_size_mb,
        CASE WHEN total_log_size_mb > 0
             THEN (active_log_size_mb / total_log_size_mb) * 100.0
        END AS log_used_percent,
        log_truncation_holdup_reason
    FROM sys.dm_db_log_stats(DB_ID())
),
vfs AS (
    -- Cumulative I/O since database/engine start (file-level stats)
    SELECT
        SUM(num_of_reads)          AS total_reads,
        SUM(io_stall_read_ms)      AS read_stall_ms,
        SUM(num_of_writes)         AS total_writes,
        SUM(io_stall_write_ms)     AS write_stall_ms
    FROM sys.dm_io_virtual_file_stats(DB_ID(), NULL)
)
SELECT
    DB_NAME()                                   AS database_name,
    res.end_time                                AS sample_end_utc,
    CAST(res.avg_cpu_percent          AS decimal(5,2))  AS cpu_pct_of_limit,
    CAST(res.avg_memory_usage_percent AS decimal(5,2))  AS memory_pct_of_limit,
    CAST(res.avg_data_io_percent      AS decimal(5,2))  AS data_io_pct_of_limit,
    CAST(res.avg_log_write_percent    AS decimal(5,2))  AS log_io_pct_of_limit,
    CAST(logstats.log_used_percent    AS decimal(5,2))  AS log_used_percent,
    data_files.data_allocated_mb,
    data_used.data_used_mb,
    data_used.data_reserved_mb,
    data_files.log_file_allocated_mb,
    logstats.total_log_size_mb,
    logstats.active_log_size_mb,
    logstats.log_truncation_holdup_reason,
    vfs.total_reads,
    vfs.read_stall_ms,
    vfs.total_writes,
    vfs.write_stall_ms
FROM res
CROSS JOIN data_files
CROSS JOIN data_used
CROSS JOIN logstats
CROSS JOIN vfs;