/*=============================================================================
  Observability — Performance drill-down after run-concurrent-scans.ps1

  Run this in wardgeneral soon after the three-session workload. It correlates
  the recent resource interval with the marked statement in Query Store, then
  reads the missing-index signal the scan produced. It does not apply a fix;
  Performance owns that decision.

  Read-only. This script creates, changes, and deletes nothing.
=============================================================================*/
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;

DECLARE @SinceUtc DATETIME2(3) = DATEADD(MINUTE, -30, SYSUTCDATETIME());

PRINT N'== 1. Recent 15-second resource samples ==';
SELECT
    end_time AS EndTimeUtc,
    avg_cpu_percent AS CpuPercent,
    avg_data_io_percent AS DataIoPercent,
    avg_log_write_percent AS LogWritePercent,
    avg_memory_usage_percent AS MemoryPercent,
    max_worker_percent AS WorkerPercent,
    max_session_percent AS SessionPercent
FROM sys.dm_db_resource_stats
WHERE end_time >= @SinceUtc
ORDER BY end_time DESC;

PRINT N'== 2. The marked scan in Query Store ==';
WITH MarkedQueries AS
(
    SELECT
        query.query_id,
        queryText.query_sql_text
    FROM sys.query_store_query_text AS queryText
    JOIN sys.query_store_query AS query
      ON query.query_text_id = queryText.query_text_id
    WHERE CHARINDEX(
        N'CH07_' + N'OBSERVABILITY_SCAN',
        queryText.query_sql_text
    ) > 0
),
RuntimeByInterval AS
(
    SELECT
        marked.query_id,
      queryPlan.plan_id,
        interval.start_time,
        interval.end_time,
        ExecutionCount = SUM(runtime.count_executions),
        CpuMs = SUM(runtime.avg_cpu_time * runtime.count_executions) / 1000.0,
        DurationMs = SUM(runtime.avg_duration * runtime.count_executions) / 1000.0,
        LogicalReads = SUM(runtime.avg_logical_io_reads * runtime.count_executions)
    FROM MarkedQueries AS marked
    JOIN sys.query_store_plan AS queryPlan
      ON queryPlan.query_id = marked.query_id
    JOIN sys.query_store_runtime_stats AS runtime
      ON runtime.plan_id = queryPlan.plan_id
    JOIN sys.query_store_runtime_stats_interval AS interval
      ON interval.runtime_stats_interval_id = runtime.runtime_stats_interval_id
    WHERE interval.end_time >= @SinceUtc
      AND runtime.execution_type = 0
    GROUP BY
        marked.query_id,
        queryPlan.plan_id,
        interval.start_time,
        interval.end_time
)
SELECT
    query_id,
    plan_id,
    start_time AS IntervalStartUtc,
    end_time AS IntervalEndUtc,
    ExecutionCount,
    CAST(CpuMs AS DECIMAL(18, 1)) AS TotalCpuMs,
    CAST(DurationMs AS DECIMAL(18, 1)) AS TotalDurationMs,
    CAST(LogicalReads AS BIGINT) AS TotalLogicalReads
FROM RuntimeByInterval
ORDER BY IntervalStartUtc DESC, query_id, plan_id;

PRINT N'== 3. Missing-index recommendation stored in the Query Store plan ==';
WITH XMLNAMESPACES
(
  DEFAULT N'http://schemas.microsoft.com/sqlserver/2004/07/showplan'
),
MarkedPlans AS
(
  SELECT
    query.query_id,
    queryPlan.plan_id,
    TRY_CONVERT(XML, queryPlan.query_plan) AS PlanXml
  FROM sys.query_store_query_text AS queryText
  JOIN sys.query_store_query AS query
    ON query.query_text_id = queryText.query_text_id
  JOIN sys.query_store_plan AS queryPlan
    ON queryPlan.query_id = query.query_id
  WHERE CHARINDEX(
    N'CH07_' + N'OBSERVABILITY_SCAN',
    queryText.query_sql_text
  ) > 0
)
SELECT
  markedPlan.query_id,
  markedPlan.plan_id,
  EstimatedImpactPercent = missingGroup.node.value(
    '@Impact', 'DECIMAL(5, 2)'
  ),
  DatabaseName = missingIndex.node.value(
    '@Database', 'NVARCHAR(128)'
  ),
  SchemaName = missingIndex.node.value('@Schema', 'NVARCHAR(128)'),
  TableName = missingIndex.node.value('@Table', 'NVARCHAR(128)'),
  ColumnUsage = columnGroup.node.value('@Usage', 'NVARCHAR(20)'),
  ColumnName = missingColumn.node.value('@Name', 'NVARCHAR(128)')
FROM MarkedPlans AS markedPlan
CROSS APPLY markedPlan.PlanXml.nodes(
  '//MissingIndexGroup'
) AS missingGroup(node)
CROSS APPLY missingGroup.node.nodes('MissingIndex') AS missingIndex(node)
CROSS APPLY missingIndex.node.nodes('ColumnGroup') AS columnGroup(node)
CROSS APPLY columnGroup.node.nodes('Column') AS missingColumn(node)
ORDER BY
  markedPlan.query_id,
  markedPlan.plan_id,
  ColumnUsage,
  ColumnName;