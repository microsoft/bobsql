SELECT 
    resource_type,
    resource_database_id,
    resource_associated_entity_id,
   -- resource_description,
    request_mode,
    request_session_id,
    request_status,
    COUNT(*) AS lock_count
FROM 
    sys.dm_tran_locks
WHERE resource_type != 'DATABASE'
GROUP BY 
    resource_type,
    resource_database_id,
    resource_associated_entity_id,
    request_mode,
    request_session_id,
    request_status
ORDER BY 
    resource_type,
    resource_database_id,
    resource_associated_entity_id,
    request_mode,
    request_session_id,
    request_status;
GO

