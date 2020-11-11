SELECT name, cast(size as bigint)*8192/(1024*1024) as size_mb, cast(max_size as bigint)*8192/(1024*1024) as max_size_mb FROM sys.database_files
GO