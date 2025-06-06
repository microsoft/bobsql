ALTER WORKLOAD GROUP [default]
WITH (GROUP_MAX_TEMPDB_DATA_MB = 1024);
GO
ALTER RESOURCE GOVERNOR RECONFIGURE;
GO

ALTER WORKLOAD GROUP [default]
WITH (GROUP_MAX_TEMPDB_DATA_MB = NULL);

ALTER RESOURCE GOVERNOR DISABLE;


SELECT group_id,
       name,
       group_max_tempdb_data_mb
FROM sys.resource_governor_workload_groups
WHERE name = 'default';
GO
SELECT group_id,
       name,
       tempdb_data_space_kb
FROM sys.dm_resource_governor_workload_groups
WHERE name = 'default';

SELECT REPLICATE('A', 1000) AS c
INTO #t;

SELECT group_id,
       name,
       tempdb_data_space_kb
FROM sys.dm_resource_governor_workload_groups
WHERE name = 'default';
GO



