select et.session_id, et.wait_type, t.task_state, et.blocking_session_id, 
et.resource_description
from sys.dm_os_waiting_tasks et
join sys.dm_exec_sessions es
on et.session_id = es.session_id
and es.is_user_process = 1
join sys.dm_os_tasks t
on t.task_address = et.waiting_task_address
go


