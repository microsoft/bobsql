--- This query will give you the difference in the filestats from max snapshot tot he Min snapshot
-- drop table tempDB.dbo.#TempFileStats
-- drop table  ##TempFileStats
IF OBJECT_ID('tempDB.dbo.##TempFileStats', 'U') IS NULL
select getdate() as runtime, db_name(database_id) as dbname,* into ##TempFileStats 
FROM sys.dm_io_virtual_file_stats(NULL,NULL)	 
where 1=2 

DECLARE @runtime datetime = GETDATE()
DECLARE @previousruntime datetime
Insert into ##TempFileStats
select @runtime, case database_id when 0 then 'RBPEX' ELSE db_name(database_id) END as dbname, 
* from sys.dm_io_virtual_file_stats(NULL,NULL)	
where database_id =0 or database_id = DB_ID()

-- Get Previous top snap
SELECT TOP(1) @previousruntime = runtime 
				FROM ##TempFileStats 
				WHERE runtime = ( SELECT max(runtime) 
										FROM ##TempFileStats 
									WHERE runtime < @runtime
										 )
				ORDER BY runtime DESC


--- File View
select datediff(ss,@previousruntime,@runtime) as SecondsSample,
a.dbname,a.database_id,a.[file_id], 
a.num_of_bytes_read/1024 - b.num_of_bytes_read/1024 as Read_KB,
a.num_of_reads - b.num_of_reads as Reads,
(a.num_of_reads - b.num_of_reads)/datediff(ss,@previousruntime,@runtime)*1.0 as Read_IOPS,
(a.io_stall_read_ms - b.io_stall_read_ms)/CASE (a.num_of_reads - b.num_of_reads) when 0 then 1 else (a.num_of_reads - b.num_of_reads) END *1.0 as read_ms
,(a.io_stall_queued_read_ms - b.io_stall_queued_read_ms)/CASE (a.num_of_reads - b.num_of_reads) when 0 then 1 else (a.num_of_reads - b.num_of_reads) END *1.0 as io_stall_queued_read_ms
,a.num_of_bytes_written/1024 - b.num_of_bytes_written/1024 as Writes_KB,
a.num_of_writes - b.num_of_writes as NumberWrites,
(a.num_of_writes - b.num_of_writes)/datediff(ss,@previousruntime,@runtime)*1.0 as Write_IOPS,
(a.io_stall_write_ms - b.io_stall_write_ms) /CASE (a.num_of_writes - b.num_of_writes) WHEN 0 then 1 else (a.num_of_writes - b.num_of_writes) END  *1.0 as write_ms
,(a.io_stall_queued_write_ms - b.io_stall_queued_write_ms) /CASE (a.num_of_writes - b.num_of_writes) WHEN 0 then 1 else (a.num_of_writes - b.num_of_writes) END  *1.0 as io_stall_queued_write_ms
--a.io_stall_queued_read_ms - b.io_stall_queued_read_ms as io_stall_queued_read_ms,
--a.io_stall_write_ms - b.io_stall_write_ms as io_stall_write_ms,
From 
    ( select * from
	##TempFileStats where runtime = @runtime) a
	INNER JOIN (
	    SELECT * FROM ##TempFileStats
		where runtime = @previousruntime) b
	ON a.database_id = b.database_id
	and a.file_id = b.file_id
ORDER BY database_id,file_id asc

--clean up table 
DELETE FROM ##TempFileStats
	WHERE runtime < @runtime

IF @previousruntime is null
Select 'Please run this again to get a diff in filestats' as Cmd