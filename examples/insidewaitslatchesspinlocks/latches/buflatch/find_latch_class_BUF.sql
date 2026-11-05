select * from sys.dm_xe_map_values
where name = 'latch_class'
and map_key = 28
go
select * from sys.dm_xe_map_values
where name = 'latch_class'
and map_value = 'BUF'
go
select * from sys.dm_os_latch_stats
GO