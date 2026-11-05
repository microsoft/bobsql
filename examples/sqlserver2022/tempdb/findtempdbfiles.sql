USE master;
GO
SELECT name, physical_name, size*8192/1024 as size_kb, growth*8192/1024 as growth_kb
FROM sys.master_files
WHERE database_id = 2;
GO