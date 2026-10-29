use test;
go
select count(*)
from
(
       SELECT
       clmns.name AS [Name],
       'Server[@Name=' + quotename(CAST(
                     serverproperty(N'Servername')
                 AS sysname),'''') + ']' + '/Database[@Name=' + quotename(db_name(),'''') + ']' + '/Table[@Name=' + quotename(tbl.name,'''') + ' and @Schema=' + quotename(SCHEMA_NAME(tbl.schema_id),'''') + ']' + '/Column[@Name=' + quotename(clmns.name,'''') + ']' AS [Urn],
       CAST(ISNULL(cik.index_column_id, 0) AS bit) AS [InPrimaryKey],
       CAST(ISNULL((select TOP 1 1 from sys.foreign_key_columns AS colfk where colfk.parent_column_id = clmns.column_id and colfk.parent_object_id = clmns.object_id), 0) AS bit) AS [IsForeignKey],
       usrt.name AS [DataType],
       ISNULL(baset.name, N'') AS [SystemType],
       CAST(CASE WHEN baset.name IN (N'nchar', N'nvarchar') AND clmns.max_length <> -1 THEN clmns.max_length/2 ELSE clmns.max_length END AS int) AS [Length],
       CAST(clmns.precision AS int) AS [NumericPrecision],
       CAST(clmns.scale AS int) AS [NumericScale],
       clmns.is_nullable AS [Nullable],
       clmns.is_computed AS [Computed],
       CAST(clmns.is_sparse AS bit) AS [IsSparse],
       CAST(clmns.is_column_set AS bit) AS [IsColumnSet],
       clmns.column_id AS [ID]
       FROM
       sys.tables AS tbl
       INNER JOIN sys.all_columns AS clmns ON clmns.object_id=tbl.object_id
       LEFT OUTER JOIN sys.indexes AS ik ON ik.object_id = clmns.object_id and 1=ik.is_primary_key
       LEFT OUTER JOIN sys.index_columns AS cik ON cik.index_id = ik.index_id and cik.column_id = clmns.column_id and cik.object_id = clmns.object_id and 0 = cik.is_included_column
       LEFT OUTER JOIN sys.types AS usrt ON usrt.user_type_id = clmns.user_type_id
       LEFT OUTER JOIN sys.types AS baset ON (baset.user_type_id = clmns.system_type_id and baset.user_type_id = baset.system_type_id) or ((baset.system_type_id = clmns.system_type_id) and (baset.user_type_id = clmns.user_type_id) and (baset.is_user_defined = 0) and (baset.is_assembly_type = 1))
) a
go
