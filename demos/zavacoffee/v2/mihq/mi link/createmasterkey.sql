-- Run on SQL Server
-- Create a master key
USE master;
GO
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<strong_password>';
GO