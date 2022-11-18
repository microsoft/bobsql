sp_configure 'show advanced options', 1;
go
reconfigure;
go
sp_configure 'max worker threads', 255;
go
reconfigure;
go