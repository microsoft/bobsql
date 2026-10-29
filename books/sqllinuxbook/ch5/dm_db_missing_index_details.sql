-- Find the current recommended missing indexes for all databases and objects
--
SELECT index_handle, database_id, object_id, equality_columns, statement
FROM sys.dm_db_missing_index_details
GO