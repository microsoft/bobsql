select (sum(total_pages)*8192)/1024/1024 as total_space_mb from sys.allocation_units
go