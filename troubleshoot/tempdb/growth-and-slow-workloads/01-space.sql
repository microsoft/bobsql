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
       SERVERPROPERTY('ProductVersion') AS product_version,
       SERVERPROPERTY('Edition') AS edition,
       SERVERPROPERTY('EngineEdition') AS engine_edition,
       osi.sqlserver_start_time AS sqlserver_start_time_server_local,
       @@SPID AS diagnostic_session_id
FROM sys.dm_os_sys_info AS osi;

SELECT @sample_time_utc AS sample_time_utc,
       f.file_id, f.name AS logical_file_name, f.type_desc,
       CONVERT(decimal(19, 2), f.size / 128.0) AS file_size_mb,
       f.max_size AS max_size_pages,
       f.growth AS growth_value,
       f.is_percent_growth,
       CONVERT(decimal(19, 2), u.unallocated_extent_page_count / 128.0) AS free_extent_mb,
       CONVERT(decimal(19, 2), u.user_object_reserved_page_count / 128.0) AS user_objects_mb,
       CONVERT(decimal(19, 2), u.internal_object_reserved_page_count / 128.0) AS internal_objects_mb,
       CONVERT(decimal(19, 2), u.version_store_reserved_page_count / 128.0) AS traditional_version_store_mb,
       CONVERT(decimal(19, 2), u.mixed_extent_page_count / 128.0) AS mixed_extents_mb
FROM sys.database_files AS f
LEFT JOIN sys.dm_db_file_space_usage AS u ON u.file_id = f.file_id
ORDER BY f.type, f.file_id;

SELECT @sample_time_utc AS sample_time_utc,
       total_log_size_in_bytes / 1048576.0 AS total_log_mb,
       used_log_space_in_bytes / 1048576.0 AS used_log_mb,
       used_log_space_in_percent
FROM sys.dm_db_log_space_usage;

SELECT @sample_time_utc AS sample_time_utc, f.file_id, f.name AS logical_file_name,
       io.num_of_reads, io.num_of_bytes_read, io.io_stall_read_ms,
       io.num_of_writes, io.num_of_bytes_written, io.io_stall_write_ms,
       io.size_on_disk_bytes
FROM sys.dm_io_virtual_file_stats(DB_ID(), NULL) AS io
JOIN sys.database_files AS f ON f.file_id = io.file_id
ORDER BY f.file_id;
