USE master;
GO
DROP DATABASE IF EXISTS howboutthemcowboys;
GO
CREATE DATABASE howbouthemcowboys;
GO
USE howboutthemcowboys;
GO
DROP TABLE IF EXISTS tothesuperbowl;
GO
CREATE TABLE tothesuperbowl (col char(1000));
go
INSERT INTO tothesuperbowl VALUES ('This is our year');
GO