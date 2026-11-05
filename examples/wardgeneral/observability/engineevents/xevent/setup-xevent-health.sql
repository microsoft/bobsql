/*=============================================================================
  Observability — Always-running Azure SQL health Extended Events session

  Creates one low-volume, database-scoped session for three signals:
    - system errors at severity 16 or higher
    - database-scoped deadlock graphs
    - client attentions (cancel, timeout, or broken connection)

  The 1 MB / 1,000-event ring buffer is intentionally bounded. STARTUP_STATE
  restarts the session when the database comes online, but ring-buffer contents
  are volatile and are lost when the session stops or the database fails over.

  This script changes database-scoped Extended Events configuration. It changes
  no application data or schema.
=============================================================================*/
SET NOCOUNT ON;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_event_sessions
    WHERE name = N'wardgeneral_health'
)
BEGIN
    CREATE EVENT SESSION [wardgeneral_health]
    ON DATABASE
    ADD EVENT sqlserver.error_reported
    (
        ACTION
        (
            sqlserver.client_app_name,
            sqlserver.client_hostname,
            sqlserver.database_name,
            sqlserver.query_hash,
            sqlserver.query_plan_hash,
            sqlserver.session_id,
            sqlserver.sql_text,
            sqlserver.username
        )
        WHERE
        (
            [severity] >= (16)
            AND [user_defined] = (0)
        )
    ),
    ADD EVENT sqlserver.database_xml_deadlock_report
    (
        ACTION
        (
            sqlserver.client_app_name,
            sqlserver.client_hostname,
            sqlserver.session_id,
            sqlserver.username
        )
    ),
    ADD EVENT sqlserver.attention
    (
        ACTION
        (
            sqlserver.client_app_name,
            sqlserver.client_hostname,
            sqlserver.database_name,
            sqlserver.query_hash,
            sqlserver.query_plan_hash,
            sqlserver.session_id,
            sqlserver.sql_text,
            sqlserver.username
        )
    )
    ADD TARGET package0.ring_buffer
    (
        SET
            MAX_EVENTS_LIMIT = (1000),
            MAX_MEMORY = (1024)
    )
    WITH
    (
        MAX_MEMORY = 2 MB,
        EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
        MAX_DISPATCH_LATENCY = 30 SECONDS,
        TRACK_CAUSALITY = ON,
        STARTUP_STATE = ON
    );

    PRINT N'Created wardgeneral_health.';
END
ELSE
BEGIN
    PRINT N'wardgeneral_health already exists — left unchanged.';
END;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.dm_xe_database_sessions
    WHERE name = N'wardgeneral_health'
)
BEGIN
    ALTER EVENT SESSION [wardgeneral_health]
    ON DATABASE
    STATE = START;

    PRINT N'Started wardgeneral_health.';
END
ELSE
BEGIN
    PRINT N'wardgeneral_health is already running.';
END;

SELECT
    SessionName = eventSession.name,
    IsRunning = CONVERT(bit, CASE WHEN activeSession.name IS NULL THEN 0 ELSE 1 END),
    eventSession.startup_state,
    eventSession.event_retention_mode_desc,
    eventSession.max_memory,
    eventSession.max_dispatch_latency
FROM sys.database_event_sessions AS eventSession
LEFT JOIN sys.dm_xe_database_sessions AS activeSession
  ON activeSession.name = eventSession.name
WHERE eventSession.name = N'wardgeneral_health';