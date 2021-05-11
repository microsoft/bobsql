select committed_kb, committed_target_kb, sql_memory_model_desc from sys.dm_os_sys_info;
go
select physical_memory_in_use_kb, large_page_allocations_kb, locked_page_allocations_kb, virtual_address_space_committed_kb from sys.dm_os_process_memory;
go
select type, pages_kb+virtual_memory_committed_kb+awe_allocated_kb as total_memory from sys.dm_os_memory_clerks
order by total_memory desc
go