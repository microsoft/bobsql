SELECT * FROM sys.dm_os_performance_counters
WHERE object_name = 'SQLServer:SQL Statistics'
ORDER BY counter_name
GO