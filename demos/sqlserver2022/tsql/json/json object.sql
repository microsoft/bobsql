-- Create a JSON object using same data
DROP TABLE IF EXISTS sql_requests_table_json_object;
GO
SELECT JSON_OBJECT('command': r.command, 'status': r.status, 'database_id': r.database_id, 'wait_type': r.wait_type, 'wait_resource': r.wait_resource, 'user': s.is_user_process) as json_object, r.command
INTO sql_requests_table_json_object
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s
ON r.session_id = s.session_id
ORDER BY r.session_id;
GO
SELECT * FROM sql_requests_table_json_object;
GO
-- see if status exists in the json path of the object
SELECT JSON_PATH_EXISTS(json_object, '$.status')
FROM sql_requests_table_json_object;