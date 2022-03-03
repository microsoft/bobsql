SELECT @@SPID;
GO
SELECT * FROM sys.dm_exec_connections
WHERE net_transport = 'TCP'
ORDER BY session_id;
GO