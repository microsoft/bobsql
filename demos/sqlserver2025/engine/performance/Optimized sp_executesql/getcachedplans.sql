-- Retrieve cached plans and their execution plans
SELECT 
    cp.cacheobjtype,
    cp.objtype,
    cp.usecounts,
    st.text AS sql_text
FROM 
    sys.dm_exec_cached_plans AS cp
CROSS APPLY 
    sys.dm_exec_sql_text(cp.plan_handle) AS st
CROSS APPLY 
    sys.dm_exec_query_plan(cp.plan_handle) AS qp
WHERE st.text LIKE '%BusinessEntityID%'
AND cp.objtype = 'Prepared';
GO
