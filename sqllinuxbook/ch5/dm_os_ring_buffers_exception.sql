-- Find all current error messages recorded by SQL Server in the ring buffer
-- [record_timestamp] is calculated by taking the current timestamp in the record (which is in clock ticks by milliseconds)
-- and subtracting this from ms_ticks in sys.dm_os_sys_info which is the number of clock ticks in ms when SQL Server was started
-- and then adding this to the current datetime. This gives you the actual datetime of the record
-- errorno, severity, and state are "shredded" from the XML record
-- errorno from the XML record is joined with sys.sysmessages to get the error message string
-- Not all error messages are "errors". Anything less than severity 16 is "informational"
DECLARE @current_ms_ticks INT
SELECT @current_ms_ticks=ms_ticks FROM sys.dm_os_sys_info
SELECT DATEADD(ms, (orb.timestamp-@current_ms_ticks), GETDATE()) as [record_timestamp],
CAST(orb.record AS XML).value('(//Exception//Error)[1]', 'varchar(10)') as [errorno],
CAST(orb.record AS XML).value('(//Exception/Severity)[1]', 'varchar(10)') as [severity],
CAST(orb.record AS XML).value('(//Exception/State)[1]', 'varchar(10)') as [state],
msg.description
FROM sys.dm_os_ring_buffers orb
INNER JOIN sys.sysmessages msg
ON msg.error = cast(record as xml).value('(//Exception//Error)[1]', 'varchar(255)')
AND msg.msglangid = 1033 -- This is for US English. Change this to your language as needed
WHERE orb.ring_buffer_type = 'RING_BUFFER_EXCEPTION'
ORDER BY record_timestamp
GO
