USE WideWorldImporters;
GO
SELECT query_id, plan_id, avg_compile_duration/1000 as avg_compile_ms, 
last_compile_duration/1000 as last_compile_ms
FROM sys.query_store_plan;
GO