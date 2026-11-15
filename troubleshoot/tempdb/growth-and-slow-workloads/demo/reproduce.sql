-- Lab only. Run once with SQLSimTools, one thread, connected to tempdb.
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF CONVERT(int, SERVERPROPERTY('EngineEdition')) NOT IN (2, 3, 4)
   OR CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) <> 17
    THROW 51000, 'This lab requires a non-production SQL Server 2025 instance.', 1;
IF DB_NAME() <> N'tempdb'
    THROW 51000, 'Connect to tempdb before running this lab.', 1;
IF APP_NAME() <> N'BobWard-TempdbGrowth-Lab'
    THROW 51000, 'Use the documented SQLSimTools command with the lab application name.', 1;
IF @@TRANCOUNT <> 0
    THROW 51000, 'Run the lab without an existing transaction.', 1;
IF (SELECT SUM(CONVERT(bigint, unallocated_extent_page_count))
    FROM sys.dm_db_file_space_usage) < 6144
    THROW 51000, 'The lab requires at least 48 MB of reusable tempdb data space. Do not grow files automatically to bypass this check.', 1;

SELECT SUM(CONVERT(bigint, size)) AS data_file_pages,
       (SELECT user_objects_alloc_page_count - user_objects_dealloc_page_count
        FROM sys.dm_db_session_space_usage WHERE session_id = @@SPID)
       + COALESCE((SELECT SUM(user_objects_alloc_page_count - user_objects_dealloc_page_count)
                   FROM sys.dm_db_task_space_usage WHERE session_id = @@SPID), 0) AS session_user_pages
INTO #TempdbGrowthBaseline
FROM sys.database_files
WHERE type = 0;

CREATE TABLE #TempdbGrowthLab
(
    row_id int NOT NULL,
    payload char(8000) NOT NULL
);

;WITH digits AS
(
    SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7)) AS d(n)
)
INSERT #TempdbGrowthLab (row_id, payload)
SELECT 1 + a.n + 8*b.n + 64*c.n + 512*d.n, REPLICATE('X', 8000)
FROM digits AS a CROSS JOIN digits AS b CROSS JOIN digits AS c CROSS JOIN digits AS d
OPTION (MAXDOP 1);

IF (SELECT COUNT_BIG(*) FROM #TempdbGrowthLab) <> 4096
    THROW 51000, 'FAIL: expected 4096 lab rows.', 1;
IF (SELECT SUM(reserved_page_count) FROM sys.dm_db_partition_stats
    WHERE object_id = OBJECT_ID(N'tempdb..#TempdbGrowthLab')) < 4096
    THROW 51000, 'FAIL: expected at least 32 MB of reserved user-object space.', 1;

SELECT N'PASS: allocation; diagnose this session during the next 90 seconds' AS lab_status,
       SYSUTCDATETIME() AS sample_time_utc, @@SPID AS lab_session_id,
       SUM(reserved_page_count) / 128.0 AS lab_reserved_mb
FROM sys.dm_db_partition_stats
WHERE object_id = OBJECT_ID(N'tempdb..#TempdbGrowthLab');
GO
-- A separate batch makes the completed allocation visible in session counters.
WAITFOR DELAY '00:01:30';
DROP TABLE #TempdbGrowthLab;
GO
SET NOCOUNT ON;
DECLARE @deadline datetime2(3) = DATEADD(SECOND, 30, SYSUTCDATETIME());
DECLARE @session_user_pages bigint;

WHILE 1 = 1
BEGIN
    SELECT @session_user_pages = su.user_objects_alloc_page_count - su.user_objects_dealloc_page_count
           + COALESCE((SELECT SUM(t.user_objects_alloc_page_count - t.user_objects_dealloc_page_count)
                       FROM sys.dm_db_task_space_usage AS t WHERE t.session_id = @@SPID), 0)
    FROM sys.dm_db_session_space_usage AS su WHERE su.session_id = @@SPID;

    IF @session_user_pages <= (SELECT session_user_pages + 256 FROM #TempdbGrowthBaseline)
        BREAK;
    IF SYSUTCDATETIME() >= @deadline
        THROW 51000, 'FAIL: session user-object space did not return within 2 MB of baseline in 30 seconds; investigate deferred deallocation.', 1;
    WAITFOR DELAY '00:00:01';
END;

SELECT N'PASS: cleanup; session user-object space returned within 2 MB of baseline' AS lab_status,
       SYSUTCDATETIME() AS sample_time_utc, @@SPID AS lab_session_id,
       @session_user_pages / 128.0 AS session_user_objects_net_mb,
       b.data_file_pages / 128.0 AS baseline_data_file_mb,
       (SELECT SUM(CONVERT(bigint, size)) / 128.0 FROM sys.database_files WHERE type = 0) AS final_data_file_mb,
       (SELECT SUM(CONVERT(bigint, unallocated_extent_page_count)) / 128.0
        FROM sys.dm_db_file_space_usage) AS final_reusable_extent_mb
FROM #TempdbGrowthBaseline AS b;

DROP TABLE #TempdbGrowthBaseline;
