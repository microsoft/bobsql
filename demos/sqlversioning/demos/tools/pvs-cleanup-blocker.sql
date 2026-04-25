-- ============================================================================
-- PVS Cleanup Blocker Diagnostic
-- Finds what's preventing PVS version cleanup in a database with ADR enabled.
-- Run this when sp_persistent_version_cleanup or the background cleaner
-- isn't reducing persistent_version_store_size_kb.
-- ============================================================================
USE texasrangerswillwinitthisyear;
GO

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Current PVS state and cleaner timestamps
-- ────────────────────────────────────────────────────────────────────────────
SELECT 
    persistent_version_store_size_kb AS PVS_Size_KB,
    current_aborted_transaction_count AS AbortedTxnCount,
    offrow_version_cleaner_start_time AS OffRowCleanerStart,
    offrow_version_cleaner_end_time AS OffRowCleanerEnd,
    aborted_version_cleaner_start_time AS AbortedCleanerStart,
    aborted_version_cleaner_end_time AS AbortedCleanerEnd,
    pvs_off_row_page_skipped_low_water_mark AS Skipped_LowWatermark,
    pvs_off_row_page_skipped_oldest_active_xdesid AS Skipped_OldestActiveXdes,
    pvs_off_row_page_skipped_min_useful_xts AS Skipped_MinUsefulXts,
    pvs_off_row_page_skipped_oldest_snapshot AS Skipped_OldestSnapshot
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID();
GO

-- ────────────────────────────────────────────────────────────────────────────
-- 2. Active snapshot transactions (most common blocker)
--    Any open SNAPSHOT or RCSI transaction pins PVS versions created
--    before its snapshot timestamp.
-- ────────────────────────────────────────────────────────────────────────────
SELECT 
    ast.session_id,
    ast.elapsed_time_seconds,
    at.transaction_begin_time,
    es.program_name,
    es.login_name,
    es.host_name,
    es.status AS session_status
FROM sys.dm_tran_active_snapshot_database_transactions ast
JOIN sys.dm_tran_active_transactions at ON ast.transaction_id = at.transaction_id
JOIN sys.dm_exec_sessions es ON ast.session_id = es.session_id
ORDER BY ast.elapsed_time_seconds DESC;
GO

-- ────────────────────────────────────────────────────────────────────────────
-- 3. All active transactions (catches non-snapshot blockers too)
--    Even non-snapshot transactions can pin PVS if they hold the
--    oldest_active_transaction watermark.
-- ────────────────────────────────────────────────────────────────────────────
SELECT 
    es.session_id,
    at.transaction_id,
    at.transaction_begin_time,
    CASE at.transaction_type
        WHEN 1 THEN 'Read/Write'
        WHEN 2 THEN 'Read-Only'
        WHEN 3 THEN 'System'
        WHEN 4 THEN 'Distributed'
    END AS transaction_type,
    CASE at.transaction_state
        WHEN 0 THEN 'Not initialized'
        WHEN 1 THEN 'Initialized'
        WHEN 2 THEN 'Active'
        WHEN 3 THEN 'Ended (read-only)'
        WHEN 4 THEN 'Commit started'
        WHEN 5 THEN 'Prepared'
        WHEN 6 THEN 'Committed'
        WHEN 7 THEN 'Rolling back'
        WHEN 8 THEN 'Rolled back'
    END AS transaction_state,
    es.program_name,
    es.login_name,
    es.host_name,
    es.open_transaction_count,
    es.transaction_isolation_level
FROM sys.dm_tran_active_transactions at
JOIN sys.dm_tran_session_transactions st ON at.transaction_id = st.transaction_id
JOIN sys.dm_exec_sessions es ON st.session_id = es.session_id
WHERE at.transaction_type != 3  -- exclude system transactions
ORDER BY at.transaction_begin_time;
GO

-- ────────────────────────────────────────────────────────────────────────────
-- 4. Sessions with implicit open transactions under RCSI
--    RCSI connections with autocommit=OFF hold implicit snapshots.
--    Common culprit: ORMs, connection pools, tooling (SSMS, pyodbc, etc.)
-- ────────────────────────────────────────────────────────────────────────────
SELECT 
    es.session_id,
    es.program_name,
    es.login_name,
    es.host_name,
    es.open_transaction_count,
    CASE es.transaction_isolation_level
        WHEN 0 THEN 'Unspecified'
        WHEN 1 THEN 'ReadUncommitted'
        WHEN 2 THEN 'ReadCommitted'
        WHEN 3 THEN 'RepeatableRead'
        WHEN 4 THEN 'Serializable'
        WHEN 5 THEN 'Snapshot'
    END AS isolation_level,
    es.last_request_start_time,
    es.last_request_end_time,
    DATEDIFF(SECOND, es.last_request_end_time, GETDATE()) AS idle_seconds
FROM sys.dm_exec_sessions es
WHERE es.open_transaction_count > 0
  AND es.is_user_process = 1
ORDER BY es.last_request_end_time;
GO

-- ────────────────────────────────────────────────────────────────────────────
-- 5. PVS records still in the store (what's being held)
-- ────────────────────────────────────────────────────────────────────────────
SELECT 
    pvs.rowset_id,
    COUNT(*) AS record_count,
    MIN(pvs.xdes_ts_tran) AS oldest_tran_ts,
    MAX(pvs.xdes_ts_tran) AS newest_tran_ts
FROM sys.dm_tran_persistent_version_store AS pvs
GROUP BY pvs.rowset_id
ORDER BY record_count DESC;
GO
