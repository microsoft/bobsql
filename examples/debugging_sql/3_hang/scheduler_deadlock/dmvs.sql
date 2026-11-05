select session_id, blocking_session_id, wait_type, wait_time, wait_resource
from sys.dm_exec_requests
go
select * from sys.dm_os_schedulers
go
select * from sys.dm_os_waiting_tasks
go
