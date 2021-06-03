-- Look at all requests and wait information
--
select session_id, command, status, wait_type, wait_time, wait_resource, last_wait_type, blocking_session_id
from sys.dm_exec_requests
go
-- wait_time is based on ticks recorded since this worker started waiting
-- we use ms_ticks from sys.dm_os_sys_info as the current "time" to do the calculation
--
select task_address, wait_started_ms_ticks, wait_resumed_ms_ticks from sys.dm_os_workers
go
select ms_ticks from sys.dm_os_sys_info
go
declare @x int
select @x = ms_ticks from sys.dm_os_sys_info
select (@x-wait_started_ms_ticks)/1000 as wait_time_ms, se.session_id, se.command
from sys.dm_os_workers so
join sys.dm_os_tasks st
on so.task_address = st.task_address
join sys.dm_exec_requests se
on se.session_id = st.session_id
where so.wait_started_ms_ticks > 0
go