-- What is my session id?
SELECT @@spid
go
-- List out the current connections, their endpoint, and port
SELECT dec.session_id, e.name, dec.local_tcp_port
FROM sys.dm_exec_connections dec
JOIN sys.endpoints e
ON e.endpoint_id = dec.endpoint_id
GO


