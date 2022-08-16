-- Show a simple JSON array
SELECT s.session_id, JSON_ARRAY(s.host_name, s.program_name)
FROM sys.dm_exec_sessions AS s
WHERE s.is_user_process = 1;
GO
-- Create a table based on a JSON array
DROP TABLE IF EXISTS sql_requests_json_array;
GO
SELECT r.session_id, JSON_ARRAY(r.command, r.status, r. database_id, r.wait_type, r.wait_resource, s.is_user_process) as json_array, r.command
INTO sql_requests_json_array
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s
ON r.session_id = s.session_id
ORDER BY r.session_id;
GO
SELECT * FROM sql_requests_json_array;
GO
-- Use ISJSON to test if JSON data exists in the array or other columns
SELECT ISJSON(json_array) as is_json, ISJSON(json_array, OBJECT) as is_json_object, ISJSON(json_array, ARRAY) as is_json_array, ISJSON(command) as is_json
FROM sql_requests_json_array;
GO
