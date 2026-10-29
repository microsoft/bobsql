/*=============================================================================
  Observability — Read the wardgeneral_health ring buffer

  Read-only. Newest events appear first. The ring buffer is bounded and
  volatile; Truncated = 1 means some XML was omitted while materializing the
  target, and events are lost when the session stops or the database fails over.
=============================================================================*/
SET NOCOUNT ON;

DECLARE @TargetData xml;

SELECT @TargetData = TRY_CONVERT(xml, target.target_data)
FROM sys.dm_xe_database_session_targets AS target
JOIN sys.dm_xe_database_sessions AS eventSession
  ON eventSession.address = target.event_session_address
WHERE eventSession.name = N'wardgeneral_health'
  AND target.target_name = N'ring_buffer';

IF @TargetData IS NULL
BEGIN
    THROW 50001, 'wardgeneral_health is not running. Run setup-xevent-health.sql first.', 1;
END;

SELECT
    TargetEventCount = @TargetData.value('(RingBufferTarget/@eventCount)[1]', 'bigint'),
    DroppedCount = @TargetData.value('(RingBufferTarget/@droppedCount)[1]', 'bigint'),
    Truncated = @TargetData.value('(RingBufferTarget/@truncated)[1]', 'bit'),
    MemoryUsedBytes = @TargetData.value('(RingBufferTarget/@memoryUsed)[1]', 'bigint');

;WITH EventData AS
(
    SELECT
        EventXml = eventNode.query('.'),
        EventName = eventNode.value('@name', 'sysname'),
        EventTimeUtc = eventNode.value('@timestamp', 'datetime2(7)')
    FROM @TargetData.nodes('RingBufferTarget/event') AS events(eventNode)
)
SELECT
    EventTimeUtc,
    EventName,
    SessionId = EventXml.value('(event/action[@name="session_id"]/value)[1]', 'int'),
    DatabaseName = EventXml.value('(event/action[@name="database_name"]/value)[1]', 'sysname'),
    ClientApp = EventXml.value('(event/action[@name="client_app_name"]/value)[1]', 'nvarchar(256)'),
    ClientHost = EventXml.value('(event/action[@name="client_hostname"]/value)[1]', 'nvarchar(256)'),
    Username = EventXml.value('(event/action[@name="username"]/value)[1]', 'nvarchar(256)'),
    ErrorNumber = EventXml.value('(event/data[@name="error_number"]/value)[1]', 'int'),
    Severity = EventXml.value('(event/data[@name="severity"]/value)[1]', 'int'),
    ErrorState = EventXml.value('(event/data[@name="state"]/value)[1]', 'int'),
    ErrorMessage = EventXml.value('(event/data[@name="message"]/value)[1]', 'nvarchar(2048)'),
    AttentionDurationMs = CONVERT(decimal(18, 3),
        EventXml.value('(event/data[@name="duration"]/value)[1]', 'bigint') / 1000.0),
    QueryHash = EventXml.value('(event/action[@name="query_hash"]/value)[1]', 'nvarchar(32)'),
    QueryPlanHash = EventXml.value('(event/action[@name="query_plan_hash"]/value)[1]', 'nvarchar(32)'),
    SqlText = EventXml.value('(event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)'),
    DeadlockXml = CASE WHEN EventName = N'database_xml_deadlock_report'
        THEN CONVERT(nvarchar(max), EventXml.query('(event/data[@name="xml_report"]/value/*)[1]'))
    END
FROM EventData
ORDER BY EventTimeUtc DESC;