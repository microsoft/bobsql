/* ============================================================================
   Ward General — Architecture (Exploring the Architecture)
   03-log-service.sql : the log service (XLOG) and its rate ceiling.  (Architecture §3)

   Architectural illustration only — no benchmarks (Performance) and no tuning. Run on
   the wardgeneral primary (query 3 returns rows only on the primary).

   Sources (accessed 2026-08-05):
     [Microsoft Learn — sys.dm_hs_database_log_rate]
       https://learn.microsoft.com/sql/relational-databases/system-functions/sys-dm-hs-database-log-rate
     [Microsoft Learn — Hyperscale performance diagnostics: reduced log rate waits]
       https://learn.microsoft.com/azure/azure-sql/database/hyperscale-performance-diagnostics#reduced-log-rate-waits
   Sources (accessed 2026-08-09):
     [Microsoft Learn — sys.dm_io_virtual_file_stats]
       https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-io-virtual-file-stats-transact-sql
     [Microsoft Learn — sys.dm_db_resource_stats]
       https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-db-resource-stats-azure-sql-database
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

PRINT N'== 1. The governed log-rate ceiling (the single-pump architectural cap) ==';
/* Every write funnels through one landing zone -> XLOG pump, so the rate is
   capped AT THE SOURCE. That is why the ceiling is flat across vCore sizes:
   it is a property of the pump, not compute size. ~100 MiB/s on standard-series,
   150 MiB/s on premium-series (May 2025). The number and its levers are Performance §5. */
SELECT
    rg.slo_name,
    rg.primary_max_log_rate                                       AS MaxLogRate_BytesPerSec,
    CAST(rg.primary_max_log_rate / 1048576.0 AS DECIMAL(6,1))     AS MaxLogRate_MiBs
FROM sys.dm_user_db_resource_governance AS rg
WHERE rg.database_id = DB_ID();
GO

PRINT N'== 2. The primary''s log write path (file_id 2) ==';
/* file_id 2 is the transaction log as the PRIMARY sees it, so these counters are
   the primary's own log writes on their way to the log service — not a view of
   the log service itself. Read them as "what the single writer has emitted."

   These are CUMULATIVE totals, not a rate. num_of_writes and MB_Written
   accumulate from the moment this replica's engine started and reset on
   restart, failover, and scale — so MB_Written cannot be compared against the
   MiB/s ceiling in query 1. To derive an actual rate, sample this DMV twice and
   divide the change in num_of_bytes_written by the change in sample_ms (Learn
   documents sample_ms for exactly that purpose). The purpose-built signal is
   avg_log_write_percent — that is query 4 below. AvgWriteLatency_ms here is
   unaffected by all this: it is a ratio of two cumulative counters, so it stays
   meaningful from a single sample.

   Do NOT read this as the consumer path. Page servers and replicas never read
   this file; they pull log blocks from the log service's broker cache (Architecture §3).
   Nothing downstream touches file_id 2.

   WHO records these counters: the primary, in SQL Server's FCB ("File Control
   Block") I/O virtualization layer — which is exactly the layer this DMV
   reports on. Hyperscale supplies its own FCB implementations so that every
   component above that layer still believes it is writing an ordinary log file
   (Socrates §3.6, §4.4). No log service component is being measured.

   WHAT it times: the DURABLE write. The log block leaves the primary over RBIO
   to the log service endpoint and the write completes once the block is
   hardened in the landing zone (Azure Premium Storage, three replicas, write
   quorum) — which is what a commit waits on. It is NOT the broker cache
   publish; the cache is filled inside the log service and never gates the
   acknowledgment, since only already-hardened blocks are disseminated
   (Socrates §4.3). Read AvgWriteLatency_ms as log harden latency. */
SELECT
    vfs.file_id,
    vfs.num_of_writes,
    vfs.num_of_bytes_written / 1024 / 1024                        AS MB_Written,
    CAST(vfs.io_stall_write_ms * 1.0
         / NULLIF(vfs.num_of_writes, 0) AS DECIMAL(9,2))          AS AvgWriteLatency_ms
FROM sys.dm_io_virtual_file_stats(DB_ID(), 2) AS vfs;
GO

PRINT N'== 3. Which component (if any) is throttling the log rate ==';
/* Read a ROW here as "this component is holding the primary's log rate down" —
   NOT as "this component's own log rate." That is the easy misreading. The log
   service tracks how far behind each consumer is; when a consumer cannot keep
   up, the log service throttles the PRIMARY so the consumer can't fall further
   behind. So role_desc names the culprit, not a producer: Storage = page server,
   Replica = HA/named secondary, GeoReplica = geo-secondary, LocalDestage = log
   service, Destage = long-term log storage — each mapping to the matching
   RBIO_RG_* wait (see §8). catchup_bytes = how far behind it is; catchup_rate =
   how fast it is closing the gap.

   This is the observable face of the back-pressure the log service applies to
   the primary.

   EXPECTED RESULT on a healthy database: exactly ONE row, role_desc = 'Primary',
   with both catchup columns 0. That means nothing is throttling. Rows for any
   other role are the interesting (unhealthy) case. Returns rows ONLY on the
   primary.

   Seeing what this returns while a component IS throttling takes a workload
   heavy enough to drive RBIO_RG_* waits, which is out of scope here. We return
   to this DMF under load in Performance §5.

   COLUMN NAMES VERIFIED BY LIVE RUN (wardgeneral, 2026-08-09). The Learn page
   contradicts itself: its "Table Returned" section lists current_max_log_rate /
   catchup_rate / catchup_bytes, but its Examples use the _bps / _distance_bytes
   forms. The EXAMPLES ARE CORRECT — the Table Returned section is a doc bug.
   Actual columns: database_id, replica_id, file_id, current_max_log_rate_bps,
   component_id, role, role_desc, catchup_rate_bps, catchup_distance_bytes,
   last_reported_time. (file_id is NULL unless role is a page server.)

   Cross-check: current_max_log_rate_bps here should equal primary_max_log_rate
   from query 1 — two independent DMVs reporting the same governed ceiling.
   Measured 2026-08-09 on HS_Gen5_8: 110,100,480 bytes/s = exactly 105.0 MiB/s
   (the real standard-series number; Learn quotes the round figure 100). */
SELECT
    lr.role_desc,
    lr.current_max_log_rate_bps                                   AS MaxLogRate_BytesPerSec,
    CAST(lr.current_max_log_rate_bps / 1048576.0 AS DECIMAL(6,1)) AS MaxLogRate_MiBs,
    lr.catchup_rate_bps,
    lr.catchup_distance_bytes,
    lr.last_reported_time
FROM sys.dm_hs_database_log_rate(DB_ID()) AS lr;
GO

PRINT N'== 4. The CURRENT log write rate (how close to the ceiling we actually are) ==';
/* Queries 1 and 3 both report what the ceiling IS. This one reports what the
   database is actually pushing through it. avg_log_write_percent is documented
   as "average transaction log writes (in MB/s) as percentage of the service
   tier limit" — a percentage OF the ceiling in query 1 — so multiplying the two
   yields a real rate. One row every 15 seconds, about an hour of history; TOP 20
   is therefore the last ~5 minutes.

   EXPECTED RESULT on the reader's quiet wardgeneral: percentages at or near
   zero. That is the point, not an anticlimax — it makes concrete that the
   ceiling is a CEILING, and that an ordinary OLTP workload lives nowhere near
   it. The log-centric architecture only becomes a constraint when a workload
   generates log fast enough to reach the cap, which is why the interesting
   version of this query runs during the bulk load in Performance §5, where the
   percentage pins near 100 and the RBIO_RG_* waits appear.

   Caveat: if the database failed over within the last 60 minutes, the view only
   returns data since that failover. */
DECLARE @MaxLogRate_MiBs DECIMAL(12,4) =
    (SELECT MAX(rg.primary_max_log_rate) / 1048576.0
     FROM sys.dm_user_db_resource_governance AS rg
     WHERE rg.database_id = DB_ID());

SELECT TOP (20)
    rs.end_time,
    rs.avg_log_write_percent                                      AS LogWrite_PctOfCeiling,
    CAST(rs.avg_log_write_percent / 100.0
         * @MaxLogRate_MiBs AS DECIMAL(6,1))                      AS LogWrite_MiBs
FROM sys.dm_db_resource_stats AS rs
ORDER BY rs.end_time DESC;
GO
