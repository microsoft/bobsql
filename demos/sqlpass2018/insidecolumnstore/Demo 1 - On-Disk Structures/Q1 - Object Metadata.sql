set nocount on
go

use [WideWorldImportersDW]
go

-----------------------------------------------------------------------------------------------------
-- Returns object details about each object in the database by joining objects and indexes to their
-- respective storage engine partition and allocation unit details.  Uses internal system views 
-- (sys.system_internals*) to show complete details of these structures.
--
select		O.[object_id]
			, I.[index_id]
			, P.[partition_number]
			, P.[partition_id]
			, quotename(S.[name]) + '.' + quotename(O.[name]) 'object_name'
			, I.[name] 'index_name'
			, I.[type_desc]
			, P.[rows]
			, AU.[allocation_unit_id]
			, AU.[type_desc] 'alloc_unit_type'
			, AU.[total_pages]
			, AU.[data_pages]
			, AU.[used_pages]
			, AU.[first_page]
			, AU.[first_iam_page]
from		sys.objects O 
				join sys.schemas S on O.[schema_id] = S.[schema_id]
				join sys.indexes I on O.[object_id] = I.[object_id]
				join sys.system_internals_partitions P on I.[object_id] = P.[object_id] and I.[index_id] = P.[index_id]
				join sys.system_internals_allocation_units AU on P.[partition_id] = AU.[container_id]
where		O.[object_id] = object_id('Fact.Sale') 
  and		P.[is_orphaned] = 0
  and		I.[type_desc] = 'CLUSTERED COLUMNSTORE'
order by	S.[name], O.[name], P.[index_id], P.[partition_number], AU.[type]
go

-----------------------------------------------------------------------------------------------------
-- Returns object details about each column in each partition of the [Fact].[Sale] table by joining
-- top-level table and index column information with internal storage engine column definitions (in
-- sys.system_internals_partition_columns).  This translation is required because the storage engine
-- representation of the partition contains different columns than the relational engine.
--
select		P.[object_id]
			, P.[index_id]
			, P.[partition_number]
			, P.[partition_id]
			, quotename(S.[name]) + '.' + quotename(O.[name]) 'object_name'
			, I.[name] 'index_name'
			, I.[type_desc]
			, IC.[index_column_id]
			, quotename(C.[name]) 'column_name'
			, C.[column_id]
			, T.[name] 'type_name'
			, PC.[partition_column_id]
from		sys.system_internals_partition_columns PC
				join sys.system_internals_partitions P on PC.[partition_id] = P.[partition_id]
				join sys.objects O on O.[object_id] = P.[object_id] 
				join sys.schemas S on S.[schema_id] = O.[schema_id]
				join sys.types T on PC.[system_type_id] = T.[system_type_id]
				join sys.indexes I on I.[index_id] = P.[index_id] and I.[object_id] = P.[object_id]
				left join sys.index_columns IC 
					 on IC.[object_id] = P.[object_id] 
					and IC.[index_id] = P.[index_id] 
					and IC.[index_column_id] = PC.[partition_column_id]
				left join sys.columns C on IC.[column_id] = C.[column_id] and IC.[object_id] = C.[object_id]
where		O.[object_id] = object_id('Fact.Sale') 
  and		P.[is_orphaned] = 0
  and		I.[type_desc] = 'CLUSTERED COLUMNSTORE'
order by	S.[name], O.[name], P.[index_id], P.[partition_number]
go