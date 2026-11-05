select waiting_task_address, session_id, wait_duration_ms, wait_type, resource_address, resource_description
from sys.dm_os_waiting_tasks;
go                                  