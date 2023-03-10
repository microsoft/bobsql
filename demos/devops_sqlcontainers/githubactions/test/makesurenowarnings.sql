SET QUOTED_IDENTIFIER ON
GO
EXEC getcustomer_byid 1;
GO
create table #x (col1 int);
GO
declare @qplan XML;
declare @x int
set @x = 0
SELECT @qplan = qp.query_plan
	FROM sys.dm_exec_cached_plans cp
    CROSS APPLY sys.dm_exec_query_plan (cp.plan_handle) qp
    INNER JOIN sys.dm_exec_procedure_stats qs ON qs.plan_handle = cp.plan_handle
	INNER JOIN sys.objects o ON qs.object_id = o.object_id
WHERE o.name = 'getcustomer_byid';
with xmlnamespaces (default 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
select @x = @qplan.exist('/ShowPlanXML/BatchSequence/Batch/Statements/StmtSimple/QueryPlan/Warnings');
insert into #x values (@x);
SELECT col1 from #x;
:EXIT(select col1 from #x)
GO
