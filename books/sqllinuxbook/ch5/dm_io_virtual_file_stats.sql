-- Find the files and associated database that have the highest avg disk latency for read operations
-- Use the DB_NAME() system function to find the database name from the id in the DMF
-- Join with the sys.master_files catalog view to find the physical file name from the file_id in the DMF
SELECT DB_NAME(ivfs.database_id), mf.physical_name, (ivfs.io_stall_read_ms/ivfs.num_of_reads) as avg_io_read_latency_ms, ivfs.num_of_reads
FROM sys.dm_io_virtual_file_stats(null,null) ivfs
INNER JOIN sys.master_files mf
ON ivfs.database_id = mf.database_id
AND ivfs.file_id = mf.file_id
WHERE num_of_reads > 0
ORDER by avg_io_read_latency_ms DESC
GO