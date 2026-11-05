USE WideWorldImporters;
GO
-- Look at the "parent" query
-- Notice this is the SELECT statement from the procedure with no OPTION for variants.
SELECT qt.query_sql_text
FROM sys.query_store_query_text qt
JOIN sys.query_store_query qq
ON qt.query_text_id = qq.query_text_id
JOIN sys.query_store_query_variant qv
ON qq.query_id = qv.parent_query_id;
GO
