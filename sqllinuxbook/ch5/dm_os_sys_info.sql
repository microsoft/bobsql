SELECT cpu_count, hyperthread_ratio, physical_memory_kb, committed_kb, committed_target_kb, max_workers_count, datediff(hour, sqlserver_start_time, getdate()) as sql_up_time_hours, affinity_type_desc, virtual_machine_type_desc, softnuma_configuration_desc, socket_count, cores_per_socket, numa_node_count, container_type_desc
FROM sys.dm_os_sys_info
GO