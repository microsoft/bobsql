SELECT qsp.plan_id, qsp.query_plan_hash, avg_duration/1000 as avg_duration_ms, 
avg_cpu_time/1000 as avg_cpu_ms, last_dop, min_dop, max_dop 
FROM sys.query_store_runtime_stats qsrs
JOIN sys.query_store_plan qsp
ON qsrs.plan_id = qsp.plan_id
ORDER by qsrs.last_execution_time;
GO
