-- Show the ring buffer types in SQL Server on Linux
--
SELECT DISTINCT(ring_buffer_type)
FROM sys.dm_os_ring_buffers
GO