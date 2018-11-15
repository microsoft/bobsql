
set nocount on
go

use [WideWorldImportersDW]
go

dbcc dropcleanbuffers
go

dbcc freesystemcache('all')
go

select * from sys.dm_column_store_object_pool
go

set statistics io on
go

select		%%physloc%%
			, [Sale Key]
			, [Customer Key]
			, [Quantity]
			, [Invoice Date Key]
from		[Fact].[Sale] with (index = 1)
where		[Invoice Date Key] = '2013-10-22'
go

select		CS.*,
			P.[object_id]
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
from		sys.dm_column_store_object_pool CS
				join sys.system_internals_partitions P 
					on CS.[object_id] = P.[object_id]
					and CS.[index_id] = P.[index_id]
					and CS.[partition_number] = P.[partition_number]
				join sys.system_internals_partition_columns PC
					on PC.[partition_id] = P.[partition_id]
				join sys.objects O on O.[object_id] = P.[object_id] 
				join sys.schemas S on S.[schema_id] = O.[schema_id]
				join sys.types T on PC.[system_type_id] = T.[system_type_id]
				join sys.indexes I on I.[index_id] = P.[index_id] and I.[object_id] = P.[object_id]
				left join sys.index_columns IC 
					 on IC.[object_id] = CS.[object_id] 
					and IC.[index_id] = CS.[index_id] 
					and IC.[index_column_id] = PC.[partition_column_id]
				left join sys.columns C on IC.[column_id] = C.[column_id] and IC.[object_id] = C.[object_id]
where		P.[object_id] = object_id('Fact.Sale') and P.[is_orphaned] = 0 and CS.[column_id] is not null
go
