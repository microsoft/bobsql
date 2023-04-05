USE todo;
GO
-- Create a new table as a detailed table for the todolist
DROP TABLE IF EXISTS todolist_details;
GO
CREATE TABLE todolist_details (detail_id int identity primary key clustered, list_id int, list_detail nvarchar(100));
GO
-- Populate data into the table and skew the number of rows for certain list_id values
-- For list_id 1 put in just a few rows
SET NOCOUNT ON;
GO
DECLARE @x int;
SET @x = 0;
WHILE (@x < 3)
BEGIN
	INSERT INTO todolist_details (list_id, list_detail) VALUES (1, 'List Detail for List ID 1');
	SET @x = @x + 1;
END;
GO
-- For list_id = 2 put in 1M rows
BEGIN TRAN;
GO
DECLARE @x int;
SET @x = 0;
WHILE (@x < 1000000)
BEGIN
	INSERT INTO todolist_details (list_id, list_detail) VALUES (2, 'List Detail for List ID 2');
	SET @x = @x + 1;
END;
GO
COMMIT TRAN;
GO
SET NOCOUNT OFF;
GO
-- Create an index on the list_id column
CREATE INDEX idx_list_id on todolist_details (list_id);
GO