sp_configure
go
sp_configure 'max server memory', 4096
go
sp_configure 'max degree of parallelism', 1
go
reconfigure
go
sp_configure 'max degree of parallelism', 0
go
reconfigure
go
