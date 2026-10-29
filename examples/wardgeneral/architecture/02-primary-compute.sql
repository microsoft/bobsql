/* ============================================================================
   Ward General — Architecture (Exploring the Architecture)
   02-primary-compute.sql : the compute replica and its RBPEX cache.  (Architecture §2)

   Architectural illustration only — no benchmarks (Performance) and no tuning. Run on
   the wardgeneral primary.

   Sources (accessed 2026-08-07):
     [Microsoft Learn — sys.dm_os_job_object]
       https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-objects/sys-dm-os-job-object-transact-sql
     [Microsoft Learn — sys.dm_user_db_resource_governance]
       https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-objects/sys-dm-user-db-resource-governor-azure-sql-database
     [Microsoft Learn — tempdb database: tempdb in Azure SQL Database]
       https://learn.microsoft.com/sql/relational-databases/databases/tempdb-database?view=sql-server-ver17#tempdb-in-azure-sql-database
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

PRINT N'== 1. The compute node''s memory ceiling (sys.dm_os_job_object) ==';
/* Azure SQL Database enforces process-level memory governance with a Windows
   Job Object, not just Resource Governor -- that's what caps the sqlservr.exe
   process itself. process_memory_limit_mb is the number that answers "how
   much memory does my compute replica have?". Current consumption / pressure
   is an observability topic (Observability). */
SELECT
    process_memory_limit_mb   AS SqlServerProcessMemoryLimit_MB
FROM sys.dm_os_job_object;
GO

PRINT N'== 2. The compute envelope (SKU shape: CPU, workers, sessions, local IOPS, ceiling) ==';
/* The primary compute replica's governed limits. The log WRITE ceiling
   (primary_max_log_rate) belongs to the log service and is shown in
   03-log-service.sql; here we show the compute-side envelope. Note
   primary_group_max_io — the local Data-IOPS budget — meters RBPEX reads +
   tempdb (the fast local path), NOT the remote page-server reads of §4. */
SELECT
    rg.slo_name,
    rg.cpu_limit                              AS vCores,
    rg.primary_pool_max_workers               AS MaxWorkers,        -- 800 on HS_Gen5_8 -- an SLO-specific Resource Governor cap, NOT the generic on-prem dynamic max-worker-threads formula (which would give 576 for 8 CPUs)
    rg.max_sessions                           AS MaxSessions,       -- 30,000 flat on Hyperscale
    rg.primary_group_max_io                   AS MaxLocalDataIOPS,  -- local SSD/tempdb budget (~32,000 on HS_Gen5_8)
    rg.max_db_max_size_in_mb / 1024 / 1024    AS MaxDbSize_TB       -- 128 TB Hyperscale ceiling
FROM sys.dm_user_db_resource_governance AS rg
WHERE rg.database_id = DB_ID();
GO

PRINT N'== 3. tempdb: sharing the local SSD budget with RBPEX (tempdb.sys.database_files) ==';
/* tempdb lives on the same local SSD path as the RBPEX cache and is metered
   by the same primary_group_max_io budget shown in §2 -- it's not a separate
   IOPS allowance. Current file size here, against the documented tempdb max
   data size ceiling for the SKU (256 GB on HS_Gen5_8). */
SELECT
    name,
    size * 8 / 1024                                              AS CurrentSize_MB,
    IIF(max_size = -1, 'Unlimited', CAST(max_size * 8 / 1024 AS varchar(20)))  AS MaxSize_MB,
    growth
FROM tempdb.sys.database_files;
GO
