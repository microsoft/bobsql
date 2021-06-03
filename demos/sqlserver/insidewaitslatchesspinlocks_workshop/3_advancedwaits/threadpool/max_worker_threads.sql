sp_configure 'max worker threads', 255
go
reconfigure;
go
sp_configure 'max worker threads', 0
go
reconfigure;
go