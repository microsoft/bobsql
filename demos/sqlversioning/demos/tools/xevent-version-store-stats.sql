-- =============================================================================
-- XEvent: tx_version_additional_stats
-- The ONLY XEvent that fires for tempdb version store activity.
-- Captures generation-side stats per database (not cleanup, not reads).
--
-- Columns:
--   database_id                        - which database generated versions
--   tempdb_version_store_inserts       - rows inserted into tempdb version store
--   tempdb_version_store_small_inserts - rows small enough for in-row PVS
--   deletes_in_ddl_transaction         - rows deleted inside DDL transactions
--   inserts_in_ddl_transaction         - rows inserted inside DDL transactions
--   heap_deforwarding_count            - heap deforwarding operations
-- =============================================================================

-- ─── Step 1: Create the session ─────────────────────────────────────────────

IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'version_store_stats')
    DROP EVENT SESSION version_store_stats ON SERVER;
GO

CREATE EVENT SESSION version_store_stats ON SERVER
ADD EVENT sqlserver.tx_version_additional_stats
(
    ACTION
    (
        sqlserver.database_id,
        sqlserver.database_name,
        sqlserver.session_id,
        sqlserver.sql_text
    )
)
ADD TARGET package0.ring_buffer
(SET max_memory = 4096)
WITH (MAX_DISPATCH_LATENCY = 5 SECONDS, STARTUP_STATE = OFF);
GO

ALTER EVENT SESSION version_store_stats ON SERVER STATE = START;
GO

PRINT 'Session started.  Generate some version store activity, then run Step 2.';
GO

-- ─── Step 2: View captured events ──────────────────────────────────────────

SELECT
    event_data.value('(event/@timestamp)[1]', 'datetime2(3)')       AS event_time,
    event_data.value('(event/data[@name="database_id"]/value)[1]', 'int') AS database_id,
    DB_NAME(event_data.value('(event/data[@name="database_id"]/value)[1]', 'int')) AS database_name,
    event_data.value('(event/data[@name="tempdb_version_store_inserts"]/value)[1]', 'bigint') AS vs_inserts,
    event_data.value('(event/data[@name="tempdb_version_store_small_inserts"]/value)[1]', 'bigint') AS vs_small_inserts,
    event_data.value('(event/data[@name="deletes_in_ddl_transaction"]/value)[1]', 'bigint') AS ddl_deletes,
    event_data.value('(event/data[@name="inserts_in_ddl_transaction"]/value)[1]', 'bigint') AS ddl_inserts,
    event_data.value('(event/data[@name="heap_deforwarding_count"]/value)[1]', 'bigint') AS heap_deforward
FROM
(
    SELECT CAST(target_data AS XML) AS target_xml
    FROM sys.dm_xe_session_targets t
    JOIN sys.dm_xe_sessions s ON t.event_session_address = s.address
    WHERE s.name = 'version_store_stats'
      AND t.target_name = 'ring_buffer'
) x
CROSS APPLY target_xml.nodes('RingBufferTarget/event') AS n(event_data)
ORDER BY event_time DESC;
GO

-- ─── Step 3: Stop and clean up ─────────────────────────────────────────────

-- ALTER EVENT SESSION version_store_stats ON SERVER STATE = STOP;
-- DROP EVENT SESSION version_store_stats ON SERVER;
