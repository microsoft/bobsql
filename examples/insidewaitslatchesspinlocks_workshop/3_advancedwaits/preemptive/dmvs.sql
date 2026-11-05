-- Let's just look at non-background tasks
--
-- last_wait_type is only valid when a task is waiting. It is cleared after the task
-- no longer is waiting. "RESOURCE MONITOR" is the exception to this rule.
--
-- Wait_resource is handy for locks, latches, OLEDB, and CXPACKET waits
--
-- blocking_session_id is only set for locks and latch waits
--
select er.session_id, er.status, er.wait_type, er.wait_time, er.wait_resource, er.last_wait_type, 
er.blocking_session_id
from sys.dm_exec_requests er
join sys.dm_exec_sessions es
on es.session_id = er.session_id
and es.is_user_process = 1
go
-- 
-- dbcc sqlperf('sys.dm_os_latch_stats', clear)
--
select * from sys.dm_os_latch_stats
where waiting_requests_count > 0
and latch_class = 'FGCB_ADD_REMOVE'
order by wait_time_ms desc
go
