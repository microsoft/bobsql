SELECT name,
       tempdb_data_space_kb, peak_tempdb_data_space_kb, 
       total_tempdb_data_limit_violation_count
FROM sys.dm_resource_governor_workload_groups;
GO
