DBCC TRACEON(3604);
GO
DBCC PAGE(defaultdb, 2, 0, 3);
GO


SELECT * FROM sys.dm_db_log_info(db_id('dbdefaultdb'));
GO

-- Break down the log file
-- 8KB is the log header
-- 1.93 for the next 3 VLFs
-- 2.17 for the last VLF

vlf_begin_offset of 6103040 + 2.17Mb = 8388608 bytes which is 8MB

database_id	file_id	vlf_begin_offset
14	2	8192
14	2	2039808
14	2	4071424
14	2	6103040



8378428

2031616 bytes
