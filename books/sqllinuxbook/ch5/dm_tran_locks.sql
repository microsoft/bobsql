-- Show locks are that requested or granted by active sessions and queries
--
SELECT resource_type, request_mode, request_request_id, resource_database_id, resource_associated_entity_id, resource_type, resource_description
FROM sys.dm_tran_locks
GO