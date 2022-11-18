dbcc sqlperf('sys.dm_os_spinlock_stats', 'clear')
go
select * from sys.dm_os_spinlock_stats order by backoffs desc
go
select * from sys.dm_xe_map_values
where name = 'sqlservr_spinlock_types'
and map_key = 183
order by map_key
GO