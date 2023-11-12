SELECT ar.replica_server_name, ag.name, dhars.role_desc, dhars.operational_state, dhars.connected_state_desc,
synchronization_health_desc, last_connect_error_description
FROM sys.dm_hadr_availability_replica_states dhars
JOIN sys.availability_groups ag
ON ag.group_id = dhars.group_id
JOIN sys.availability_replicas ar
ON ar.replica_id = dhars.replica_id;
GO

SELECT ar.replica_server_name, ag.name, dhdrs.is_primary_replica, dhdrs.synchronization_state_desc, 
dhdrs.synchronization_health_desc, dhdrs.is_commit_participant, dhdrs.suspend_reason_desc,
dhdrs.last_sent_lsn, dhdrs.last_sent_time, dhdrs.last_hardened_lsn, dhdrs.last_hardened_time, 
dhdrs.last_commit_lsn, dhdrs.last_commit_time
FROM sys.dm_hadr_database_replica_states dhdrs
JOIN sys.availability_groups ag
ON ag.group_id = dhdrs.group_id
JOIN sys.availability_replicas ar
ON ar.replica_id = dhdrs.replica_id
GO

BACKUP LOG texasrangerswschamps TO DISK = 'texasrangerswschamps_log.bak' WITH INIT;
GO
SELECT name, log_reuse_wait_desc FROM sys.databases where name = 'texasrangerswschamps';
GO
