CREATE EVENT SESSION [tracespagesplits] ON SERVER
ADD EVENT sqlserver.page_split(
ACTION (sqlserver.session_id, sqlserver.sql_text, sqlserver.client_app_name, sqlserver.database_id))
ADD TARGET package0.event_file(SET filename=N'pagesplits.xel')
WITH (MAX_DISPATCH_LATENCY=5 SECONDS,STARTUP_STATE=OFF)
GO
