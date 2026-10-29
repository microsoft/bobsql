/*=============================================================================
  Observability — Monitor and troubleshoot Azure SQL connections

  Run this script against the logical server's master database. Both system
  views are unavailable from user-database connections. The queries are
  read-only and return every database visible to the caller.

  Change the two values below to inspect another UTC window or return more
  detailed events. Data retention is at most 30 days.
=============================================================================*/
SET NOCOUNT ON;

DECLARE @Hours int = 24;
DECLARE @EventLimit int = 200;

IF @Hours NOT BETWEEN 1 AND 720
    THROW 50001, '@Hours must be between 1 and 720.', 1;

IF @EventLimit NOT BETWEEN 1 AND 5000
    THROW 50001, '@EventLimit must be between 1 and 5000.', 1;

DECLARE @WindowStartUtc datetime2(7) = DATEADD(hour, -@Hours, SYSUTCDATETIME());

SELECT TOP (@EventLimit)
    database_name,
    start_time,
    end_time,
    event_category,
    event_type,
    event_subtype,
    event_subtype_desc,
    severity,
    event_count,
    description,
    additional_data
FROM sys.event_log
WHERE end_time >= @WindowStartUtc
ORDER BY start_time DESC, database_name, event_type, event_subtype;

SELECT
    database_name,
    start_time,
    end_time,
    success_count,
    total_failure_count,
    connection_failure_count,
    terminated_connection_count,
    throttled_connection_count
FROM sys.database_connection_stats
WHERE end_time >= @WindowStartUtc
ORDER BY start_time DESC, database_name;