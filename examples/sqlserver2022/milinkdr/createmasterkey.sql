-- Run on SQL Server
-- Create a master key
USE MASTER;
GO
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$StrongPassw0rd';
GO