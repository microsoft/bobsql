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
-- Do a INSERT but not parallel
--
INSERT INTO howboutthemcowboys
SELECT * FROM howboutthemcowboys_base
GO
-- Do we have a compressed rowgroup yet?
--
SELECT * FROM sys.column_store_row_groups
GO
-- What about delta bitmaps
--
DELETE from howboutthemcowboys where col1 < 500000
GO
-- Do we have a compressed rowgroup yet?
--
SELECT * FROM sys.column_store_row_groups
GO
-- What does partitions vs internal partitions look like?
--
SELECT * FROM sys.partitions where object_id = object_id('howboutthemcowboys')
GO
SELECT * FROM sys.system_internals_partitions where object_id = object_id('howboutthemcowboys')
GO
-- What does the Delta Bitmap look like?
--
SELECT * FROM sys.system_internals_allocation_units where container_id = 72057594052804608
go
-- Dump out the first page in the Delta Bitmap CL index
--
DBCC TRACEON(3604)
GO
DBCC PAGE('gocowboyscci', 1, 14864, 3)
go