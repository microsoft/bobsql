USE [WideWorldImporters]
GO
SELECT event_time, action_id, session_id, object_name, server_principal_name, database_principal_name, statement, client_ip, application_name
FROM sys.fn_get_audit_file ('/var/opt/mssql/auditsqlserver*.*',default,default)
GO