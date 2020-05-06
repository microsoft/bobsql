-- Step 1: Only show requests with active queries except for this one
SELECT er.session_id, er.command, er.status, er.wait_type, er.cpu_time, er.logical_reads, eqsx.query_plan, t.text
FROM sys.dm_exec_requests er
CROSS APPLY sys.dm_exec_query_statistics_xml(er.session_id) eqsx
CROSS APPLY sys.dm_exec_sql_text(er.sql_handle) t
WHERE er.session_id <> @@SPID
GO
 
-- Step 2: What does the plan profile look like for the active query
SELECT session_id, physical_operator_name, node_id, thread_id, row_count, estimate_row_count
FROM sys.dm_exec_query_profiles
WHERE session_id <> @@SPID
ORDER BY session_id, node_id DESC
GO

-- Step 3: Go back and look at the plan and query text for a clue
SELECT er.session_id, er.command, er.status, er.wait_type, er.cpu_time, er.logical_reads, eqsx.query_plan, t.text
FROM sys.dm_exec_requests er
CROSS APPLY sys.dm_exec_query_statistics_xml(er.session_id) eqsx
CROSS APPLY sys.dm_exec_sql_text(er.sql_handle) t
WHERE er.session_id <> @@SPID
GO