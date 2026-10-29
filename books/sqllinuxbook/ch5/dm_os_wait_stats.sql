-- Show the number of waits by type and the avg wait time of that type sorted by the highest avg wait types
-- Note that some waits are "normal" because they are part of background tasks that naturally waits as part of its execution
SELECT wait_type, waiting_tasks_count, (wait_time_ms/waiting_tasks_count) as avg_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE waiting_tasks_count > 0
ORDER BY avg_wait_time_ms DESC
GO