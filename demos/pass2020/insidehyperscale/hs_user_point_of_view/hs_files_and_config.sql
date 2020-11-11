-- Hyperscale has no "max size" but we typically build out multiple files
--
SELECT name, cast(size as bigint)*8192/(1024*1024) as size_mb, cast(max_size as bigint)*8192/(1024*1024) as max_size_mb 
FROM sys.database_files;
GO
-- See the limits of HS using these DMVs
--
SELECT slo_name, cpu_limit, max_dop, max_db_max_size_in_mb, primary_max_log_rate FROM 
sys.dm_user_db_resource_governance;
GO
SELECT memory_limit_mb FROM sys.dm_os_job_object;
GO
SELECT * FROM sys.dm_io_virtual_file_stats(db_id(), NULL);
GO
ALTER DATABASE bwazuresqlhyper MODIFY (SERVICE_OBJECTIVE = 'HS_GEN5_2');
GO
SELECT slo_name, cpu_limit, max_dop, max_db_max_size_in_mb, primary_max_log_rate FROM sys.dm_user_db_resource_governance;
GO

