select resource_type, resource_database_id, resource_lock_partition, request_mode, request_type, request_session_id  
from sys.dm_tran_locks
go