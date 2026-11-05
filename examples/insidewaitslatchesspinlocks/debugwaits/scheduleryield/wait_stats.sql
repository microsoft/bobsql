--dbcc sqlperf('sys.dm_os_wait_stats', clear)
--go
--
-- Notice that signal_wait_time_ms is almost the same as wait_time_ms
-- this is because the majority of "waiting" for SOS_SCHEDULER_YIELD is the time
-- to be signalled to run again. You are not waiting on anything else
--
-- Let's clear the wait stats first
--
dbcc sqlperf('sys.dm_os_wait_stats' , CLEAR)
go
select wait_type, waiting_tasks_count, cast((cast(wait_time_ms as float)/waiting_tasks_count) as float) as avg_wait_time_ms, 
wait_time_ms, 
signal_wait_time_ms
from sys.dm_os_wait_stats
where wait_type = 'SOS_SCHEDULER_YIELD'
and waiting_tasks_count > 0
go
-- what do other wait types signal times look compared to wait times?
select wait_type, wait_time_ms, signal_wait_time_ms
from sys.dm_os_wait_stats
where waiting_tasks_count > 0
go