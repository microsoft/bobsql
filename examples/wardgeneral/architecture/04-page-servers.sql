/* ============================================================================
   Ward General — Architecture (Exploring the Architecture)
   04-page-servers.sql : the page-server tier and GetPage@LSN.  (Architecture §4)

   Architectural illustration only — no benchmarks (Performance) and no tuning.

   Run against ANY wardgeneral compute replica — primary, HA secondary, or named
   replica (verified live, 2026-08-09). Unlike 03-log-service.sql §3
   (sys.dm_hs_database_log_rate, primary-only), both queries here are per-
   compute-node telemetry: each replica keeps its own independent buffer pool +
   RBPEX cache and issues its own GetPage@LSN calls, so each accumulates its own
   page-server read counters. Run the same query on two different replicas and
   expect two different answers — that divergence IS the teaching point (and is
   exactly why continuous priming exists, Architecture §5/§9).

   PERMISSIONS — admin, or VIEW DATABASE STATE. Query 2 also inspects OTHER
   sessions, which needs server-level state; without it it returns zero rows and
   no error -- which is ALSO the expected result on a quiet database, so the
   permission failure is invisible. See README.md.

   Sources (accessed 2026-08-05; permissions verified 2026-08-10):
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

PRINT N'== 1. The page-server slices (each owns up to a 128 GB slice) ==';
/* Every row for this database with file_id <> 2 is a page server — one row per
   file, each owning a slice of up to ~128 GB. This is file
   anatomization: a 128 TB database is thousands of these slices. The compute
   replica never writes here directly (the log service applies log to them), so
   "writes" in this DMF are simulated; the durable copy lives in Azure Storage (§5).

   A page server also writes modified pages down to Azure Storage itself — a
   BACKGROUND TASK that keeps its RBPEX in sync with durable storage so that cold
   pages can be evicted from the cache and still be read back later. Despite the
   name of the wait below, this is NOT the SQL Server checkpoint process, and it
   is not what makes a transaction durable (the log service already did that).
   That write never shows up here or anywhere else on compute; the write counters
   above are only the simulated one. The one compute-visible signal that a page
   server is falling behind on its write-down is the RBIO_RG_STORAGE_CHECKPOINT
   wait, which throttles the PRIMARY's log rate (Observability §3 identification, Performance §5
   ceilings/levers) — a throttle, not an I/O count.

   THIS REPLICA'S OWN VIEW, NOT A DATABASE-WIDE VIEW. num_of_reads/MB_Read here
   reflect the page-server reads issued by whichever replica you're connected
   to — the primary, an HA secondary, or a named replica. A freshly failed-over
   or freshly created replica whose BP/RBPEX haven't warmed (or aren't yet
   continuously primed) will show a very different read pattern here than the
   primary serving the same steady-state workload. */
SELECT
    vfs.file_id,
    vfs.num_of_reads,
    vfs.num_of_bytes_read / 1024 / 1024                          AS MB_Read,
    CAST(vfs.io_stall_read_ms * 1.0
         / NULLIF(vfs.num_of_reads, 0) AS DECIMAL(9,2))          AS AvgReadLatency_ms
FROM sys.dm_io_virtual_file_stats(DB_ID(), NULL) AS vfs
WHERE vfs.database_id = DB_ID()      -- exclude the local RBPEX cache rows (database_id 0)
  AND vfs.file_id <> 2               -- exclude the transaction log
ORDER BY vfs.file_id;
GO

PRINT N'== 2. Page-server reads in flight — the remote GetPage@LSN path ==';
/* When a page isn't in the buffer pool or RBPEX, the replica fetches it from the
   owning page server via GetPage@LSN — a remote read exposed as page_server_reads
   and surfacing as a PAGEIOLATCH_* wait (§8). Crucially, page-server reads are
   NOT counted against the governed local Max Data IOPS (that meters local SSD
   only, §2) — they spend a different, latency-bound currency (Performance §3).

   Also a per-replica view: sys.dm_exec_requests only ever shows requests
   executing on the node you're connected to. Run this on an HA or named
   replica to see THAT replica's in-flight page-server reads, not the
   primary's.

   EXPECT ZERO ROWS ON A QUIET wardgeneral — and that IS the result. A page-
   server read needs a DOUBLE miss: not in the buffer pool AND not in RBPEX.
   The Getting Started seed is small enough to sit entirely in this replica's RBPEX, so
   nothing has to go remote. Trying to force it with DBCC DROPCLEANBUFFERS
   does not work either: verified live 2026-08-09, dropping the buffer pool
   and then scanning the largest table (clinical.Observation) moved no page-
   server counters at all. The command runs, the buffer pool empties, and the
   read is served one tier down by RBPEX — it never reaches a page server.
   That failure is worth sitting with, because it is the tier boundary made
   visible: the local cache absorbed everything. The reliable way to see a
   real GetPage@LSN is a COLD cache — a freshly created named replica scanned
   on first touch, before it warms. Performance does exactly that, on a database
   grown large enough for it to matter. */
SELECT
    r.session_id, r.command,
    r.logical_reads, r.reads AS physical_reads, r.page_server_reads,
    SUBSTRING(t.text, 1, 80) AS sql_head
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.session_id <> @@SPID AND r.page_server_reads > 0
ORDER BY r.page_server_reads DESC;
GO
