/*=============================================================================
  Observability — Stop and remove the wardgeneral_health event session

  Dropping the session discards its volatile ring-buffer contents.
=============================================================================*/
SET NOCOUNT ON;

IF EXISTS
(
    SELECT 1
    FROM sys.dm_xe_database_sessions
    WHERE name = N'wardgeneral_health'
)
BEGIN
    ALTER EVENT SESSION [wardgeneral_health]
    ON DATABASE
    STATE = STOP;
END;

IF EXISTS
(
    SELECT 1
    FROM sys.database_event_sessions
    WHERE name = N'wardgeneral_health'
)
BEGIN
    DROP EVENT SESSION [wardgeneral_health]
    ON DATABASE;

    PRINT N'Dropped wardgeneral_health.';
END
ELSE
BEGIN
    PRINT N'wardgeneral_health was not found.';
END;