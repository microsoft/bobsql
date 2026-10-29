DBCC FREEPROCCACHE
GO
USE WideWorldImporters
GO
ALTER DATABASE SCOPED CONFIGURATION SET LAST_QUERY_PLAN_STATS = ON
GO
SELECT st.text, cp.plan_handle, qp.query_plan, qps.query_plan
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) AS qp
CROSS APPLY sys.dm_exec_query_plan_stats(cp.plan_handle) AS qps
GO