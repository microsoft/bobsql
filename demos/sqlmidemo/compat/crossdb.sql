USE master;
GO
DROP DATABASE IF EXISTS todo_archive;
GO
CREATE DATABASE todo_archive;
GO
USE todo_archive;
GO
SELECT * FROM todo.dbo.todolist;
GO