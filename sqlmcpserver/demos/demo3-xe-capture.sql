-- =============================================================================
-- Demo 3 — "Under the hood": capture the T-SQL the SQL MCP Server (DAB) emits.
--
-- The point of this demo:
--   * read_records  -> DAB emits a PARAMETERIZED query (sp_executesql, bound @param).
--   * describe_entities -> emits NO SQL at all (it's an in-memory config read).
-- Run this against the SAME instance DAB connects to (localhost, AdventureWorks).
-- Windows auth. Use the MSSQL extension (preferred) or SSMS.
-- =============================================================================

-- 1) (Re)create a lightweight ring-buffer session filtered to our view's queries.
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'dab_mcp_capture')
    DROP EVENT SESSION [dab_mcp_capture] ON SERVER;
GO

CREATE EVENT SESSION [dab_mcp_capture] ON SERVER
ADD EVENT sqlserver.rpc_completed (
    ACTION (sqlserver.sql_text, sqlserver.database_name, sqlserver.client_app_name, sqlserver.username)
    WHERE (sqlserver.database_name = N'AdventureWorks'
       AND sqlserver.like_i_sql_unicode_string(sqlserver.sql_text, N'%ProductComponents%'))
),
ADD EVENT sqlserver.sql_batch_completed (
    ACTION (sqlserver.sql_text, sqlserver.database_name, sqlserver.client_app_name, sqlserver.username)
    WHERE (sqlserver.database_name = N'AdventureWorks'
       AND sqlserver.like_i_sql_unicode_string(sqlserver.sql_text, N'%ProductComponents%'))
)
ADD TARGET package0.ring_buffer (SET max_events_limit = 50)
WITH (MAX_DISPATCH_LATENCY = 1 SECONDS, TRACK_CAUSALITY = OFF);
GO

ALTER EVENT SESSION [dab_mcp_capture] ON SERVER STATE = START;
GO

-- 2) Now, in the agent, run the cold-open beat:
--      a) describe_entities            -> watch: NOTHING is captured (no SQL).
--      b) read_records Touring-1000    -> watch: ONE rpc_completed with a bound @param.
--
--    Then run the reader below to show the captured statement(s).

-- 3) Read what was captured (run after the agent calls the tools).
;WITH x AS (
    SELECT CAST(t.target_data AS XML) AS xml_data
    FROM sys.dm_xe_session_targets t
    JOIN sys.dm_xe_sessions s ON s.address = t.event_session_address
    WHERE s.name = N'dab_mcp_capture' AND t.target_name = N'ring_buffer'
)
SELECT
    e.n.value('(@timestamp)[1]', 'datetime2')                                   AS event_time,
    e.n.value('(@name)[1]', 'nvarchar(60)')                                     AS event_name,
    e.n.value('(action[@name="username"]/value)[1]', 'nvarchar(200)')           AS [login],
    e.n.value('(action[@name="client_app_name"]/value)[1]', 'nvarchar(200)')    AS app_name,
    e.n.value('(action[@name="sql_text"]/value)[1]', 'nvarchar(max)')           AS sql_text,
    e.n.value('(data[@name="statement"]/value)[1]', 'nvarchar(max)')            AS statement
FROM x
CROSS APPLY x.xml_data.nodes('//RingBufferTarget/event') AS e(n)
ORDER BY event_time;
-- Expect: a single rpc_completed whose statement is like
--   exec sp_executesql N'SELECT ... FROM [mcp].[vProductComponents] ... WHERE [ProductModel] = @param0 ...',
--                      N'@param0 ...', @param0 = N'Touring-1000'
-- The value 'Touring-1000' is a BOUND PARAMETER, not concatenated into the text. That is NL2DAB.

-- 4) Cleanup (run after the demo).
-- ALTER EVENT SESSION [dab_mcp_capture] ON SERVER STATE = STOP;
-- DROP EVENT SESSION [dab_mcp_capture] ON SERVER;
