sp_configure 'max server memory', 4800
go
reconfigure
go

sp_configure 'max server memory', 1024
go
reconfigure
go

sp_configure 'max server memory', 0
go
reconfigure
go
