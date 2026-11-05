USE [bigdb]
GO
SELECT file_id, FILEGROUP_NAME(filegroup_id) filegroup, total_page_count, allocated_extent_page_count
FROM sys.dm_db_file_space_usage
GO
