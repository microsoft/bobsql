select session_id, wait_type, wait_time, wait_resource, blocking_session_id
from sys.dm_exec_requests;
go