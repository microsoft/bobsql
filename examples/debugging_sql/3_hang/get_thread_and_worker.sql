SELECT t.*, w.*
FROM sys.dm_os_threads t
JOIN sys.dm_os_workers w
ON t.worker_address = w.worker_address
WHERE os_thread_id = 2044
GO