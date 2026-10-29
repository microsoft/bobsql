-- Find the total memory used within the SQL Server Engine, the total amount of buffer pool usage,
-- and the target that SQL Server believes it can grow to
-- 
SELECT counter_name, cntr_value FROM sys.dm_os_performance_counters
WHERE object_name = 'SQLServer:Memory Manager'
AND counter_name IN ('Database Cache Memory (KB)', 'Total Server Memory (KB)', 'Target Server Memory (KB)')
GO