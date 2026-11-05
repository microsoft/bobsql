/* ============================================================================
   Performance, stage 1: focused before/after evidence.
   Run in the MSSQL extension, SSMS, or go-sqlcmd before and after each load.
   Observability owns the interpretation of these surfaces.
   ============================================================================ */

SET NOCOUNT ON;

SELECT
    DatabaseName = DB_NAME(),
    Edition = DATABASEPROPERTYEX(DB_NAME(), 'Edition'),
    ServiceObjective = DATABASEPROPERTYEX(DB_NAME(), 'ServiceObjective'),
    CapturedAtUtc = SYSUTCDATETIME();

SELECT TOP (60)
    end_time,
    avg_cpu_percent,
    avg_data_io_percent,
    avg_log_write_percent,
    max_worker_percent,
    max_session_percent
FROM sys.dm_db_resource_stats
ORDER BY end_time DESC;

SELECT
    counter_name,
    cntr_value
FROM sys.dm_os_performance_counters
WHERE counter_name IN (N'RBPEX cache hit ratio', N'RBPEX cache hit ratio base')
ORDER BY counter_name;

SELECT TOP (20)
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    signal_wait_time_ms
FROM sys.dm_db_wait_stats
WHERE wait_type IN (N'PAGEIOLATCH_SH', N'PAGEIOLATCH_EX', N'WRITELOG')
   OR wait_type LIKE N'RBIO_RG[_]%'
ORDER BY wait_time_ms DESC;

SELECT
    ProcedureName = OBJECT_SCHEMA_NAME(q.object_id) + N'.' + OBJECT_NAME(q.object_id),
    Executions = SUM(rs.count_executions),
    AverageDurationMs = CAST(
        SUM(CONVERT(DECIMAL(38, 4), rs.avg_duration) * rs.count_executions)
        / NULLIF(SUM(rs.count_executions), 0) / 1000.0
        AS DECIMAL(18, 3)),
    AverageCpuMs = CAST(
        SUM(CONVERT(DECIMAL(38, 4), rs.avg_cpu_time) * rs.count_executions)
        / NULLIF(SUM(rs.count_executions), 0) / 1000.0
        AS DECIMAL(18, 3)),
    LastExecutionUtc = MAX(rs.last_execution_time)
FROM sys.query_store_query AS q
JOIN sys.query_store_plan AS p
    ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats AS rs
    ON rs.plan_id = p.plan_id
WHERE q.object_id IN
(
    OBJECT_ID(N'clinical.GetPatientChart'),
    OBJECT_ID(N'clinical.RecordVitals'),
    OBJECT_ID(N'clinical.PlaceMedicationOrder'),
    OBJECT_ID(N'clinical.FileLabResult'),
    OBJECT_ID(N'clinical.AddClinicalNote')
)
  AND rs.last_execution_time >= DATEADD(MINUTE, -30, SYSUTCDATETIME())
GROUP BY q.object_id
ORDER BY ProcedureName;
