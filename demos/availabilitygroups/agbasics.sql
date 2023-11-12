SELECT ag.name, replica_server_name, endpoint_url, availability_mode_desc, failover_mode_desc, session_timeout, create_date, 
primary_role_allow_connections_desc, secondary_role_allow_connections_desc
FROM sys.availability_replicas ar
JOIN sys.availability_groups ag
ON ar.group_id = ag.group_id
GO
SELECT aglia.dns_name, aglipa.ip_address, aglipa.network_subnet_ip
FROM sys.availability_group_listeners aglia
JOIN sys.availability_group_listener_ip_addresses aglipa
ON aglia.listener_id = aglipa.listener_id;
GO