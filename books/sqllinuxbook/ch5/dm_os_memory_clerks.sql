-- Find out which components in SQL Server are using the most memory
--
SELECT type, name, (pages_kb+virtual_memory_committed_kb+awe_allocated_kb) total_memory_kb 
FROM sys.dm_os_memory_clerks
ORDER BY total_memory_kb DESC
GO