USE bwdb;
GO
declare @qplan XML;
SELECT  @qplan = qp.query_plan
	FROM sys.dm_exec_cached_plans cp
    CROSS APPLY sys.dm_exec_query_plan (cp.plan_handle) qp
    INNER JOIN sys.dm_exec_procedure_stats qs ON qs.plan_handle = cp.plan_handle
	INNER JOIN sys.objects o ON qs.object_id = o.object_id
WHERE o.name = 'getcustomer_byid';
with xmlnamespaces (default 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
select @qplan.query('/ShowPlanXML/BatchSequence/Batch/Statements/StmtSimple/QueryPlan/Warnings');   