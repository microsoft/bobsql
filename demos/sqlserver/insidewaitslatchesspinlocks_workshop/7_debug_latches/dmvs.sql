select et.session_id, et.waiting_task_address, et.exec_context_id, et.wait_duration_ms, 
et.wait_type, et.resource_address, et.blocking_task_address,
et.blocking_session_id, et.blocking_exec_context_id,
et.resource_description
from sys.dm_os_waiting_tasks et
join sys.dm_exec_sessions es
on et.session_id = es.session_id
and es.is_user_process = 1
go

