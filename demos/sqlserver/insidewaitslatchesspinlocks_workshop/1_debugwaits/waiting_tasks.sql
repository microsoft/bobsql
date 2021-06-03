-- Let's just look at anyone waiting
--
-- What is the interesting behavior of LAZYWRITER_SLEEP for its wait_duration_ms
-- compared to other requests?
select session_id, exec_context_id, wait_type, wait_duration_ms 
from sys.dm_os_waiting_tasks
go



