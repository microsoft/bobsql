select session_id, exec_context_id, wait_type, wait_duration_ms 
from sys.dm_os_waiting_tasks
where wait_type = 'LAZYWRITER_SLEEP' or wait_type = 'CHECKPOINT_QUEUE'
GO
go
