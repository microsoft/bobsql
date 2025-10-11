SELECT SERVERPROPERTY('Edition');
GO
SELECT cpu_count, (committed_target_kb/1024/1024) as committed_target_gb
FROM sys.dm_os_sys_info;
GO