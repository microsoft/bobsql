/* ============================================================================
   Ward General — Architecture (Exploring the Architecture)
   01-four-tiers.sql : three of the four tiers, made visible in one DMF.  (Architecture §1)

   Architectural illustration only — no benchmarks (Performance) and no tuning. These
   DMVs return as an operational toolkit in Observability and as tuning instruments in
   Performance; here they just make the architecture concrete. Run on the
   wardgeneral primary.

   Sources (accessed 2026-08-05):
     [Microsoft Learn — Hyperscale performance diagnostics: virtual file stats and IO accounting]
       https://learn.microsoft.com/azure/azure-sql/database/hyperscale-performance-diagnostics#virtual-file-stats-and-io-accounting
     [Microsoft Learn — Hyperscale distributed functions architecture]
       https://learn.microsoft.com/azure/azure-sql/database/hyperscale-architecture
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

PRINT N'== Three of the four tiers, made visible via sys.dm_io_virtual_file_stats ==';
/* In Hyperscale the file map IS the storage tier. One DMF, three tiers:
     database_id = 0  -> compute-local RBPEX SSD cache  (primary compute, §2)
     file_id     = 2  -> transaction log (XLOG)         (log service, §3)
     all other rows   -> the database's data files, each served by a page
                         server (1:1, up to 128 GB per slice)  (§4)
   The durable copy of those data files lives in Azure Storage (§5).

   The data-file rows name the FILE, but what they measure is the PATH: reads
   issued from compute against these files are remote page-server reads, and
   the writes are simulated (compute never writes directly to a page server).
   Each data file is fronted by one page server (§4).

   database_id = 0 is RBPEX ONLY -- source-confirmed 2026-08-06. These rows are
   the Buffer Pool Extension files backing the local SSD cache; tempdb is NOT
   reported here (tempdb shares the local SSD and is metered together with
   RBPEX reads in the governed Max Data IOPS, but that is IOPS accounting, a
   different thing from these file rows). Multiple database_id = 0 rows = more
   than one BPE file.

   The RBPEX counters ARE real (source-confirmed 2026-08-06): RbpeFCB derives
   from FCB, and RBPEX I/O completions run the same FCB accounting path as data
   and log files -- genuinely measured, unlike the SIMULATED write counters on
   the page-server rows. But read them with two quirks in mind:

     1. num_of_reads on database_id = 0 is a PAGE count, not an I/O count.
        Learn: reads served from the local SSD cache "are accounted as multiple
        individual 8-KB reads ... the number of read IOs seen against the local
        SSD cache might be larger than the actual number of IOs performed by
        the engine." A 4 MB read-ahead served from RBPEX appears as ~512 reads,
        not 1. Do not call it IOPS. Use num_of_bytes_read for volume -- that
        one does not suffer the inflation.
     2. A read that spans cached and uncached pages is SPLIT across two rows:
        the RBPEX-covered pages are credited to database_id 0 and only the
        remainder to the page-server row. So partial hits contribute
        proportionally to both sides rather than counting wholly as a miss.

   Latency is deliberately NOT computed here. Because of quirk 1, dividing
   io_stall_read_ms by num_of_reads is invalid on the database_id = 0 rows, and
   comparing that number against the page-server rows would overstate the
   local-vs-remote gap. Latency belongs to Observability (PAGEIOLATCH_* waits and the
   page-server read columns in the execution DMVs) and Performance.

   size_on_disk_bytes is bytes ACTUALLY ALLOCATED, and it means something
   different per tier -- which is exactly why it is worth showing here:
     - RBPEX rows: these are SPARSE files, so this is what the cache has
       consumed so far, NOT its ceiling. The ceiling is the local SSD
       provisioned for the compute size (§2) and is not visible here.
     - Data-file rows: the allocated size of the slice, which grows in 10 GB
       increments and never auto-shrinks (§4/§5). This is the number you pay
       on -- Hyperscale bills allocated storage, not the 128 TB max (§1).
   Learn: "For sparse files, this number is the actual number of bytes on the
   disk that are used." For allocated vs used vs max, see 05-file-storage.sql
   (note sys.database_files does NOT contain the RBPEX rows at all). */
SELECT
    CASE WHEN vfs.database_id = 0 THEN N'Local RBPEX SSD cache'
         WHEN vfs.file_id     = 2 THEN N'Transaction log (XLOG)'
         ELSE N'Data file (served by page server)' END AS Tier,
    vfs.database_id, vfs.file_id,
    CAST(vfs.size_on_disk_bytes / 1024.0 / 1024.0
         AS DECIMAL(18,2))                            AS AllocatedOnDisk_MB,
    vfs.num_of_reads, vfs.num_of_writes,
    vfs.num_of_bytes_read  / 1024 / 1024              AS MB_Read,
    vfs.num_of_bytes_written / 1024 / 1024            AS MB_Written
FROM sys.dm_io_virtual_file_stats(DB_ID(), NULL) AS vfs
ORDER BY
    CASE WHEN vfs.database_id = 0 THEN 1   -- compute  (§2)
         WHEN vfs.file_id     = 2 THEN 2   -- log      (§3)
         ELSE 3 END,                       -- storage  (§4)
    vfs.file_id;
GO
