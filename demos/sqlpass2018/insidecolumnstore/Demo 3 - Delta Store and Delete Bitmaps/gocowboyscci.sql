USE gocowboyscci
GO
-- Now create the table with CCI
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
-- Let's insert < 102400 rows a few times and see what we get
--
INSERT INTO howboutthemcowboys 
SELECT TOP 102399 * FROM howboutthemcowboys_base
GO
-- Do we have a compressed rowgroup yet?
--
SELECT * FROM sys.column_store_row_groups
GO
-- Do it again and we just add to the current OPEN Delta RG
--
INSERT INTO howboutthemcowboys 
SELECT TOP 102399 * FROM howboutthemcowboys_base
GO
-- Do we have a compressed rowgroup yet?
--
SELECT * FROM sys.column_store_row_groups
GO
-- What partitions exist now?
-- There are 3 now: 1 for compressed segments (empty now), and 1 for Delta RG, and 1 for the delta bitmap (now empty)
SELECT * FROM sys.system_internals_partitions where object_id = object_id('howboutthemcowboys')
GO
-- What does the Delta RG look like?
--
SELECT * FROM sys.system_internals_allocation_units where container_id = 72057594051166208
go
-- Let's dump out the first data page
--
DBCC TRACEON(3604)
GO
DBCC PAGE('gocowboyscci', 1, 21488, 3)
GO
-- OK, now fill up this Delta RG past 1M rows
-- Run this until we spill over the 1M mark
--
DECLARE @x INT
SET @x = 0
WHILE (@x < 10)
BEGIN
INSERT INTO howboutthemcowboys 
SELECT TOP 102399 * FROM howboutthemcowboys_base
SET @x = @x + 1
END
GO
-- What does RGs look like now?
--
SELECT * FROM sys.column_store_row_groups
GO
-- What partitions do we have?
-- We now have 4
-- 1 for CCI compressed (still empty); 1 for CLOSED which will become TOMBSTONE; 1 for new OPEN, and 1 for Delta Bitmap (empty)
SELECT * FROM sys.system_internals_partitions where object_id = object_id('howboutthemcowboys')
GO
