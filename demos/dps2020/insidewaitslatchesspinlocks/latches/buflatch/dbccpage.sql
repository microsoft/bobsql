select * from sys.dm_os_buffer_descriptors
go
dbcc traceon(3604)
go
dbcc page(1,1,1,3)
go
select * from sys.dm_os_latch_stats
go