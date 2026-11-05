/* ============================================================================
   Ward General — Architecture (Exploring the Architecture)
   05-file-storage.sql : the durable tier — where the 128 TB lives.  (Architecture §5)

   Architectural illustration only — no benchmarks (Performance) and no tuning. Run on
   the wardgeneral primary. Operational backup/restore policy is High Availability and Resiliency.

   Sources (accessed 2026-08-05):
     [Microsoft Learn — Manage file space for databases in Azure SQL Database]
       https://learn.microsoft.com/azure/azure-sql/database/file-space-manage
     [Microsoft Learn — Automated backups for Hyperscale databases]
       https://learn.microsoft.com/azure/azure-sql/database/hyperscale-automated-backups-overview
   Source (accessed 2026-08-09):
     [Microsoft Learn — Azure SQL Database Hyperscale FAQ]
       https://learn.microsoft.com/azure/azure-sql/database/service-tier-hyperscale-frequently-asked-questions-faq
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

PRINT N'== 1. Allocated vs used vs max, per file (you pay on ACTUAL allocation) ==';
/* Each data file (type_desc = ROWS) is backed by a page-server slice (§4) whose
   durable copy lives in Azure Storage. Allocation grows automatically in 10 GB
   steps and never auto-shrinks; the gap between allocated and used is reclaimable
   only by a manual shrink (Performance / Learn). The key architectural point: billing is
   on allocated storage, not the 128 TB max_size ceiling.

   Read that literally: you are billed on SpaceAllocated_MB, not SpaceUsed_MB.
   Learn puts it beyond doubt in the backup docs -- data storage "is already
   billed as allocated database storage". Two consequences the reader will meet
   on their own small database: (a) the 10 GB step is also the billing
   granularity, so one row past the current allocation adds 10 GB to the bill,
   and on a tiny database that rounding is most of the storage cost; (b) because
   allocation never falls on its own, the bill ratchets -- deleting data does not
   reduce it. Note too that AUTO_SHRINK has NO EFFECT on Hyperscale, so reclaiming
   the gap is always a deliberate manual act, never something to leave switched on.

   Note what is NOT on this list: any decision of yours. You cannot manage or
   define files or filegroups on Hyperscale -- data files are added automatically
   to PRIMARY. You never choose the count and you never choose the size, which is
   why the file-layout planning that occupies a traditional SQL Server DBA has no
   equivalent here. A large table's pages land in whatever files proportional fill
   puts them in. (Hyperscale FAQ, accessed 2026-08-09.)

   The growth rule is not a service heuristic you have to take on faith -- it is
   stamped on the file metadata below, in 8 KB pages. Decode the numbers:

       max_size = 16777216 pages  = 128 GB   <- the page-server slice size (§4)
       growth   =  1310720 pages  =  10 GB   <- fixed step, not a percentage
       is_percent_growth = 0

   So a data file is capped at exactly one page server's worth of data. It is
   created at 10 GB, autogrows in 10 GB steps up to 128 GB, and then it is done --
   to store more, the service adds another file (and with it, another page server).
   That is the whole algorithm, and it is ordinary SQL Server autogrow; the only
   part Hyperscale does differently is deciding when to add the next file. Learn
   documents the 10 GB step and the 128 GB page-server slice separately but never
   states the per-file cap -- the file metadata does.

   Mind the direction of that claim, because it is easy to get backwards. Because
   both ceilings are 128 GB, a data file can never OUTGROW a single page server:
   there is no such thing as one big file sharded across several page servers. Many
   page servers scale a large DATABASE, not a large FILE. The mapping is strict in
   both directions -- one file, one page server -- confirmed with the Azure SQL
   product team, 2026-08-10. Learn's performance-diagnostics page says the opposite
   ("for larger files, multiple page servers are used"); that sentence is incorrect.

   is_sparse = 1 on every Hyperscale data file, and that is the tell for how the
   whole tier is stitched together. The file the primary has locally is a SPARSE
   STUB -- it occupies almost nothing, because none of the data is really there.
   What the stub carries is the file's true LOGICAL size, and the bytes behind
   that size live in Azure Storage, reachable through the page server that owns
   the file. So the engine gets to keep running its ordinary file code -- a file
   with a size, a max size, and an autogrow step, exactly as this query reports
   it -- while the physical bytes have been moved out from under it. That is the
   same trick, at the file level, that the rest of this area shows at the page
   level: the engine believes it is reading a page from a file; it is really
   getting one from a page server. (Sparse-file semantics themselves are ordinary
   SQL Server / NTFS behaviour -- see the sys.master_files reference -- but Learn
   does not document their use in Hyperscale. Read the value yourself below.)

   Note the RBPEX local-cache files are NOT in this view at all (they appear only
   as database_id = 0 in sys.dm_io_virtual_file_stats -- see 01-four-tiers.sql). */
SELECT
    df.file_id,
    df.is_sparse,
    CAST(FILEPROPERTY(df.name, 'SpaceUsed') AS BIGINT) * 8 / 1024.0   AS SpaceUsed_MB,
    CAST(df.size    AS BIGINT) * 8 / 1024.0                           AS SpaceAllocated_MB,
    CASE WHEN df.max_size = -1 THEN NULL
         ELSE CAST(df.max_size AS BIGINT) * 8 / 1024.0 END            AS MaxSize_MB,
    CASE WHEN df.is_percent_growth = 1 THEN NULL
         ELSE CAST(df.growth AS BIGINT) * 8 / 1024.0 END              AS GrowthStep_MB,
    df.is_percent_growth
FROM sys.database_files AS df
WHERE df.type_desc = 'ROWS'   -- data files only; the log is the log service's story (§3)
ORDER BY df.file_id;
GO

PRINT N'== 2. Whole-database allocation vs the 128 TB ceiling ==';
/* Total allocated data storage (what you pay for) against the Hyperscale max.
   Restore is size-independent because backups are snapshot-based at the storage
   tier — no data copy, regardless of database size (High Availability and Resiliency). */
SELECT
    CAST(SUM(CAST(df.size AS BIGINT)) * 8 / 1024.0 / 1024.0 AS DECIMAL(12,2))  AS DataAllocated_GB,
    CAST(SUM(CAST(FILEPROPERTY(df.name, 'SpaceUsed') AS BIGINT)) * 8
             / 1024.0 / 1024.0 AS DECIMAL(12,2))                              AS DataUsed_GB,
    (SELECT rg.max_db_max_size_in_mb / 1024 / 1024
     FROM sys.dm_user_db_resource_governance AS rg
     WHERE rg.database_id = DB_ID())                                          AS MaxSize_TB
FROM sys.database_files AS df
WHERE df.type_desc = 'ROWS';
GO
