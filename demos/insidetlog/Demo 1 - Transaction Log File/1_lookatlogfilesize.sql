USE defaultdb;
GO
SELECT name, size*8192/(1024*1024) AS size_in_MB, growth*8192/(1024*1024) AS growth_in_MB
FROM sys.database_files
WHERE file_id = 2;
GO

