/* ============================================================================
  Performance, Demo 3: observe which query feedback features intervene.

  Executions 1 and 2 return actual Showplan XML automatically. Compare
  estimated and actual rows, the Sort warning, and MemoryGrantInfo. The DMV
  summary reports grants and spills. Query Store reports whether CE feedback,
  memory grant feedback, or both produced persisted feedback.
   ============================================================================ */

SET NOCOUNT ON;
SET STATISTICS TIME ON;
GO

IF OBJECT_ID(N'clinical.DemonstrateMemoryGrantFeedback', N'P') IS NULL
   OR OBJECT_ID(N'clinical.ShiftReportArchive', N'U') IS NULL
  THROW 51025, 'Run 01-setup.sql first.', 1;
GO

CREATE TABLE #MemoryGrantEvidence
(
    ExecutionNumber INT NOT NULL,
    CachedExecutionCount BIGINT NOT NULL,
    PlanGenerationNumber BIGINT NOT NULL,
    GrantKB BIGINT NOT NULL,
    UsedGrantKB BIGINT NOT NULL,
    SpillPages BIGINT NOT NULL,
    ElapsedTimeMs DECIMAL(19, 3) NOT NULL
);

DECLARE @ExecutionNumber INT = 1;

WHILE @ExecutionNumber <= 8
BEGIN
  IF @ExecutionNumber <= 2
    SET STATISTICS XML ON;

    EXEC clinical.DemonstrateMemoryGrantFeedback;

  IF @ExecutionNumber <= 2
    SET STATISTICS XML OFF;

    INSERT INTO #MemoryGrantEvidence
    SELECT TOP (1)
        @ExecutionNumber,
        qs.execution_count,
        qs.plan_generation_num,
        qs.last_grant_kb,
        qs.last_used_grant_kb,
        qs.last_spills,
        CONVERT(DECIMAL(19, 3), qs.last_elapsed_time / 1000.0)
    FROM sys.dm_exec_query_stats AS qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
    WHERE st.objectid = OBJECT_ID(N'clinical.DemonstrateMemoryGrantFeedback')
      AND qs.last_grant_kb > 0
    ORDER BY qs.last_execution_time DESC, qs.statement_start_offset;

    SET @ExecutionNumber += 1;
END;

SELECT
    ExecutionNumber,
    CachedExecutionCount,
    PlanGenerationNumber,
    GrantMB = CONVERT(DECIMAL(19, 2), GrantKB / 1024.0),
    UsedGrantMB = CONVERT(DECIMAL(19, 2), UsedGrantKB / 1024.0),
    SpillPages,
    SpillMB = CONVERT(DECIMAL(19, 2), SpillPages * 8.0 / 1024.0),
    ElapsedTimeMs
FROM #MemoryGrantEvidence
ORDER BY ExecutionNumber;
GO

SELECT
  q.query_id,
  p.plan_id,
  pf.feature_desc,
  pf.state_desc,
  pf.feedback_data,
  pf.create_time,
  pf.last_updated_time
FROM sys.query_store_query AS q
INNER JOIN sys.query_store_plan AS p
  ON p.query_id = q.query_id
INNER JOIN sys.query_store_plan_feedback AS pf
  ON pf.plan_id = p.plan_id
WHERE q.object_id = OBJECT_ID(N'clinical.DemonstrateMemoryGrantFeedback')
ORDER BY pf.create_time, pf.plan_feedback_id;
GO

SET STATISTICS TIME OFF;
GO