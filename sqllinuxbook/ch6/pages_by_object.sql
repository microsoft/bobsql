USE [bigdb]
GO
SELECT OBJECT_NAME(object_id) object_name, allocated_page_file_id, count(*) total_pages_allocated
FROM sys.dm_db_database_page_allocations(DB_ID('bigdb'), NULL, NULL, NULL, 'DETAILED')
GROUP BY object_id, allocated_page_file_id
ORDER BY total_pages_allocated DESC
GO
