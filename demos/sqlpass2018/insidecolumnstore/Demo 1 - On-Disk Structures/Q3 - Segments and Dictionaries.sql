
set nocount on
go

use [WideWorldImportersDW]
go

-----------------------------------------------------------------------------------------------------
-- This query demonstrates viewing individual segment metadata about columns in [Fact].[Sale]
--
select		O.[object_id]
			, I.[index_id]
			, P.[partition_number]
			, P.[partition_id]
			, quotename(S.[name]) + '.' + quotename(O.[name]) 'object_name'
			, I.[name] 'index_name'
			, I.[type_desc]
			, IC.[index_column_id]
			, quotename(C.[name]) 'column_name'
			, C.[column_id]
			, PC.max_length
			, CS.*
from		sys.column_store_segments CS 
				join sys.system_internals_partitions P on P.[partition_id] = CS.[partition_id]
				left join sys.system_internals_partition_columns PC 
					 on CS.[partition_id] = PC.[partition_id]
					and CS.[column_id] = PC.[partition_column_id]
				join sys.objects O on P.[object_id] = O.[object_id]
				join sys.schemas S on O.[schema_id] = S.[schema_id]
				join sys.indexes I 
					 on I.[index_id] = P.[index_id] 
					and I.[object_id] = P.[object_id]
				left join sys.index_columns IC 
					 on IC.[object_id] = I.[object_id] 
					and IC.[index_id] = I.[index_id] 
					and IC.[index_column_id] = PC.[partition_column_id]
				left join sys.columns C 
					 on IC.[column_id] = C.[column_id] 
					and IC.[object_id] = C.[object_id]				
where		O.[object_id] = object_id('Fact.Sale') and P.[is_orphaned] = 0
order by	S.[name], O.[name], P.[index_id], P.[partition_number]
go

-----------------------------------------------------------------------------------------------------
-- This query demonstrates viewing individual dictionary metadata about columns in [Fact].[Sale]
--
select		O.[object_id]
			, I.[index_id]
			, P.[partition_number]
			, P.[partition_id]
			, quotename(S.[name]) + '.' + quotename(O.[name]) 'object_name'
			, I.[name] 'index_name'
			, I.[type_desc]
			, IC.[index_column_id]
			, quotename(C.[name]) 'column_name'
			, C.[column_id]
			, PC.max_length
			, CS.*
from		sys.column_store_dictionaries CS 
				join sys.system_internals_partitions P on P.[partition_id] = CS.[partition_id]
				left join sys.system_internals_partition_columns PC 
					 on CS.[partition_id] = PC.[partition_id]
					and CS.[column_id] = PC.[partition_column_id]
				join sys.objects O on P.[object_id] = O.[object_id]
				join sys.schemas S on O.[schema_id] = S.[schema_id]
				join sys.indexes I 
					 on I.[index_id] = P.[index_id] 
					and I.[object_id] = P.[object_id]
				left join sys.index_columns IC 
					 on IC.[object_id] = I.[object_id] 
					and IC.[index_id] = I.[index_id] 
					and IC.[index_column_id] = PC.[partition_column_id]
				left join sys.columns C 
					 on IC.[column_id] = C.[column_id] 
					and IC.[object_id] = C.[object_id]				
where		O.[object_id] = object_id('Fact.Sale') and P.[is_orphaned] = 0
order by	S.[name], O.[name], P.[index_id], P.[partition_number]
go
