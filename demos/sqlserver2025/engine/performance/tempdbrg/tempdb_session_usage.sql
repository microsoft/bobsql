SELECT 
    ssu.session_id,
    es.program_name AS appname,
    ssu.user_objects_alloc_page_count * 8 AS user_objects_alloc_kb,
    ssu.internal_objects_alloc_page_count * 8 AS internal_objects_alloc_kb
FROM 
    sys.dm_db_session_space_usage AS ssu
JOIN 
    sys.dm_exec_sessions AS es ON ssu.session_id = es.session_id
WHERE 
    (ssu.user_objects_alloc_page_count > 0 OR ssu.internal_objects_alloc_page_count > 0)
