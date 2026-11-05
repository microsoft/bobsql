sp_configure 'show advanced', 1;
go
reconfigure;
go
sp_configure 'max degree of parallelism', 0;
go
reconfigure;
go