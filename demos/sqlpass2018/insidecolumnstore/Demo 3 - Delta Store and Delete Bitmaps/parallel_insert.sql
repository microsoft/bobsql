use gocowboyscci
go
-- Create the table again
--
DROP TABLE IF EXISTS howboutthemcowboys
GO
-- Create the base table with a unique key but colors that only have two types: 'Silver' and 'Blue'
--
CREATE TABLE howboutthemcowboys(col1 int, 
color char(20) not null, 
rowdate datetime,
index cowboyscci clustered columnstore
)
GO
-- Do a parallel INSERT
--
INSERT INTO howboutthemcowboys WITH (TABLOCK)
SELECT * FROM howboutthemcowboys_base
GO
-- What does RGs look like now?
--
SELECT * FROM sys.column_store_row_groups
GO
-- What do partitions look like?
--
SELECT siau.allocation_unit_id, sip.*, siau.* 
FROM sys.system_internals_partitions sip
JOIN sys.system_internals_allocation_units siau
ON sip.partition_id = siau.container_id
where sip.object_id = object_id('howboutthemcowboys')
GO
-- How do I compact these?
--
ALTER INDEX cowboyscci on howboutthemcowboys REORGANIZE -- WITH (COMPRESS_ALL_ROW_GROUPS = ON)
GO
SELECT * FROM sys.column_store_row_groups
GO
-- What do partitions look like?
-- Notice the LOB_DATA has more pages to account for TOMBSTONE rowgroups
SELECT siau.allocation_unit_id, sip.*, siau.* 
FROM sys.system_internals_partitions sip
JOIN sys.system_internals_allocation_units siau
ON sip.partition_id = siau.container_id
where sip.object_id = object_id('howboutthemcowboys')
GO
