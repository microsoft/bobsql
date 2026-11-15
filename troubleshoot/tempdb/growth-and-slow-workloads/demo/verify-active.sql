SET NOCOUNT ON;

IF CONVERT(int, SERVERPROPERTY('EngineEdition')) NOT IN (2, 3, 4)
   OR CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) <> 17
    THROW 51000, 'This lab requires SQL Server 2025.', 1;
IF DB_NAME() <> N'tempdb'
    THROW 51000, 'Connect to tempdb before verifying the lab.', 1;
IF HAS_PERMS_BY_NAME(NULL, NULL, 'VIEW SERVER PERFORMANCE STATE') <> 1
    THROW 51000, 'VIEW SERVER PERFORMANCE STATE is required to verify other sessions.', 1;

;WITH active_tasks AS
(
    SELECT session_id,
           SUM(user_objects_alloc_page_count - user_objects_dealloc_page_count) AS user_pages
    FROM sys.dm_db_task_space_usage
    GROUP BY session_id
)
SELECT s.session_id, s.program_name, s.status AS session_status,
       r.status AS request_status, r.wait_type, r.blocking_session_id,
       (su.user_objects_alloc_page_count - su.user_objects_dealloc_page_count
        + COALESCE(t.user_pages, 0)) / 128.0 AS user_objects_net_mb
INTO #LabOwners
FROM sys.dm_exec_sessions AS s
JOIN sys.dm_db_session_space_usage AS su ON su.session_id = s.session_id
LEFT JOIN active_tasks AS t ON t.session_id = s.session_id
LEFT JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id
WHERE s.program_name = N'BobWard-TempdbGrowth-Lab'
  AND s.session_id <> @@SPID;

IF (SELECT COUNT(*) FROM #LabOwners) <> 1
    THROW 51000, 'FAIL: expected exactly one lab request. Start one SQLSimTools run and verify during its 90-second hold.', 1;
IF NOT EXISTS (SELECT 1 FROM #LabOwners WHERE user_objects_net_mb >= 32)
    THROW 51000, 'FAIL: lab owner has not reached 32 MB of user-object allocation.', 1;

SELECT N'PASS: lab owner has at least 32 MB of user-object allocation' AS lab_status,
       SYSUTCDATETIME() AS sample_time_utc, *
FROM #LabOwners;
DROP TABLE #LabOwners;
