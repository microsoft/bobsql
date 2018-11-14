USE [WideWorldImporters]
GO
SELECT o.name as table_name, i.name as index_name, i.type_desc, i.is_primary_key, i.is_unique, c.name as column_name
FROM sys.objects o
INNER JOIN sys.indexes i
ON o.object_id = i.object_id
AND o.type = 'U'
AND o.name = 'Orders'
INNER JOIN sys.index_columns ic
ON ic.index_id = i.index_id
AND ic.object_id = i.object_id
INNER JOIN sys.columns c
ON ic.column_id = c.column_id
AND c.object_id = i.object_id
ORDER BY table_name, index_name
GO