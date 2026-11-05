USE AdventureWorks;
GO
EXEC sys.sp_query_store_clear_hints @query_id = <query id>;
GO