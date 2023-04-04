USE master;
GO
DROP DATABASE IF EXISTS todo;
GO
CREATE DATABASE todo;
GO
USE todo;
GO
-- Create a todolist table
--
DROP TABLE IF EXISTS todolist;
GO
CREATE TABLE todolist (
    list_id int identity primary key clustered,
    list_item nvarchar(100),
    list_status int DEFAULT (0), -- 0 means started; 1 means complete
    list_assigned sysname,
    list_date datetime DEFAULT (GETDATE())
);
-- Populate the table with some data to start
--
SET NOCOUNT ON;
GO
DECLARE @x int;
SET @x = 0;
WHILE (@x < 1000)
BEGIN
    INSERT INTO todolist (list_item, list_assigned) VALUES ('New todolist item', user_name());
    SET @x = @x + 1;
END;
GO
SET NOCOUNT OFF;
GO