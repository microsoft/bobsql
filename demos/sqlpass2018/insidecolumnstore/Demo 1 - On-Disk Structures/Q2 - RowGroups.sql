
set nocount on
go

use [WideWorldImportersDW]
go

-----------------------------------------------------------------------------------------------------
-- Returns details about row groups in the [Fact].[Sale] table
--
select		O.[object_id]
			, I.[index_id]
			, P.[partition_number]
			, P.[partition_id]
			, quotename(S.[name]) + '.' + quotename(O.[name]) 'object_name'
			, I.[name] 'index_name'
			, I.[type_desc]
			, RG.*
from		sys.column_store_row_groups RG 
				join sys.system_internals_partitions P 
					 on RG.[object_id] = P.[object_id] 
					and RG.[index_id] = P.[index_id] 
					and RG.[partition_number] = P.[partition_number]
				join sys.objects O on P.[object_id] = O.[object_id]
				join sys.schemas S on O.[schema_id] = S.[schema_id]
				join sys.indexes I on I.[index_id] = P.[index_id] and I.[object_id] = P.[object_id]
where		O.[object_id] = object_id('Fact.Sale') and P.[is_orphaned] = 0
order by	S.[name], O.[name], P.[index_id], P.[partition_number], RG.[row_group_id]
go
