-- show all wait stats
--
select * from sys.dm_os_wait_stats
order by wait_type
go
-- Show only wait stats that have occurred
--
select * from sys.dm_os_wait_stats
where waiting_tasks_count > 0
order by wait_type
go
-- Show only wait stats that have an avg of 10ms or higher
-- orderd by count
--
select wait_type, waiting_tasks_count, wait_time_ms/waiting_tasks_count as avg_wait_time_ms
from sys.dm_os_wait_stats
where waiting_tasks_count > 0
and wait_time_ms/waiting_tasks_count >= 10
order by waiting_tasks_count desc
go
-- Let's clear the stats
--
dbcc sqlperf('sys.dm_os_wait_stats', clear)
go