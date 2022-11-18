select session_id, physical_operator_name, p.cpu_time_ms, p.object_id, p.index_id
FROM sys.dm_exec_query_profiles p
order by cpu_time_ms desc;
go

select object_name(74);
go

