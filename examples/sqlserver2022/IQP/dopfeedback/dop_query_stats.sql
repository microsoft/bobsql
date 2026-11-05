USE WideWorldImporters;
GO
-- The hash value of 4128150668158729174 should be fixed for the plan from the workload
SELECT qsp.query_plan_hash, avg_duration/1000 as avg_duration_ms, 
avg_cpu_time/1000 as avg_cpu_ms, last_dop, min_dop, max_dop, qsrs.count_executions
FROM sys.query_store_runtime_stats qsrs
JOIN sys.query_store_plan qsp
ON qsrs.plan_id = qsp.plan_id
and qsp.query_plan_hash = CONVERT(varbinary(8), cast(4128150668158729174 as bigint))
ORDER by qsrs.last_execution_time;
GO
