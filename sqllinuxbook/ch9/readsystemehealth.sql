SELECT DATEADD(minute, DATEDIFF(minute,getutcdate(),getdate()), timestamp_utc) as local_datetime, *
FROM sys.fn_xe_file_target_read_file('/var/opt/mssql/log/system_health*.xel', NULL, NULL, NULL)
ORDER BY local_datetime DESC
GO