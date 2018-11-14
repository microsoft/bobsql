USE [wideworldimportersdw]
GO
SELECT OBJECT_NAME(object_id) as table_name, name, type_desc
FROM sys.indexes
-- type = 5 means clustered columnstore index
WHERE type = 5
GO