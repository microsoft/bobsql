USE AdventureWorks;
GO
EXEC sys.sp_query_store_set_hints
 @query_id = 4,
 @query_hints = N'OPTION (USE HINT (''ABORT_QUERY_EXECUTION''))';
GO