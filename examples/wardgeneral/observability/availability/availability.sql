/*
    Ward General — Observability
    Observe current Hyperscale availability evidence.

    Read-only. This script does not fail over, scale, or change replicas.
*/

SET NOCOUNT ON;

PRINT '=== 1. Hyperscale replica topology ===';

SELECT
    replica_id,
    replica_role_desc,
    replica_server_name,
    replica_database_name,
    is_local,
    local_database_id,
    parent_replica_id
FROM sys.dm_hs_database_replicas(DB_ID())
ORDER BY
    CASE replica_role_desc
        WHEN N'Primary' THEN 1
        WHEN N'High availability secondary' THEN 2
        WHEN N'Named replica' THEN 3
        WHEN N'Geo secondary' THEN 4
        ELSE 5
    END,
    replica_database_name;

PRINT '';
PRINT '=== 2. Replica synchronization evidence visible from this connection ===';

SELECT
    replica_id,
    database_id,
    is_local,
    is_primary_replica,
    synchronization_state_desc,
    synchronization_health_desc,
    database_state_desc,
    is_suspended,
    suspend_reason_desc,
    last_commit_time,
    secondary_lag_seconds
FROM sys.dm_database_replica_states
WHERE database_id = DB_ID()
ORDER BY is_local DESC, is_primary_replica DESC, replica_id;

PRINT '';
PRINT '=== 3. Current connection ===';

SELECT
    DatabaseName = DB_NAME(),
    ConnectedServer = CONVERT(NVARCHAR(128), SERVERPROPERTY('ServerName')),
    Updateability = DATABASEPROPERTYEX(DB_NAME(), 'Updateability'),
    DatabaseStatus = DATABASEPROPERTYEX(DB_NAME(), 'Status'),
    SampledAtUtc = SYSUTCDATETIME();

PRINT '';
PRINT 'Continuous priming is a platform behavior; these DMVs do not expose a direct priming-status column.';