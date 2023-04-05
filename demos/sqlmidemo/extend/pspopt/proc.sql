USE todo;
GO
CREATE OR ALTER PROCEDURE gettodolistdetails
@list_id INT
AS
SELECT * FROM todolist_details
WHERE list_id = @list_id;
GO