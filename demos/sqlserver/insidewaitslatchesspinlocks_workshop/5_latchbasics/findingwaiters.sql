-- Find all wait types that are latches
select * from sys.dm_os_wait_stats
where wait_type like '%LATCH%'
go
-- Show me all latch classes
select * from sys.dm_os_latch_stats
go
-- The wait_type for a BUF latch is
-- PAGELATCH_XX or PAGEIOLATCH_XX. For a non-BUF latch it is LATCH_XX
-- The wait_resource is a pageno for a PAGELATCH
-- and "class" and "address" for LATCH_XX
select er.session_id, command, wait_type, wait_resource, 
wait_time, blocking_session_id
from sys.dm_exec_requests er
join sys.dm_exec_sessions es
on er.session_id = es.session_id
where es.is_user_process = 1;
go
-- resource_address for a latch is the Latch class
-- resource_description is latch class "name"
select wt.session_id, exec_context_id, wait_duration_ms, 
wait_type, resource_address, blocking_task_address,
blocking_session_id, blocking_exec_context_id,
resource_description
from sys.dm_os_waiting_tasks wt
join sys.dm_exec_sessions es
on wt.session_id = es.session_id
where es.is_user_process = 1
go