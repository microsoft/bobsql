SELECT [database_name] = xe_file.xml_data.value('(/event/action[@name=''database_name'']/value)[1]','[nvarchar](128)'),
[read_size] = CAST(xe_file.xml_data.value('(/event/data[@name=''size'']/value)[1]', '[nvarchar](128)') AS INT),
[file_path] = xe_file.xml_data.value('(/event/data[@name=''path'']/value)[1]', '[nvarchar](128)')
--xe_file.xml_data
FROM
(
SELECT [xml_data] = CAST(event_data AS XML)
FROM sys.fn_xe_file_target_read_file('/var/opt/mssql/log/tracesqlreads*.xel', null, null, null)
) AS xe_file
GO