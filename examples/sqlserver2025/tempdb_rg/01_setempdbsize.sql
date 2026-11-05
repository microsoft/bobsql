USE master;
GO

-- Alter tempdb data files to set size to 64MB for total of 512MB
ALTER DATABASE tempdb 
MODIFY FILE (NAME = tempdev, SIZE = 64MB);
GO

ALTER DATABASE tempdb 
MODIFY FILE (NAME = temp2, SIZE = 64MB);
GO

ALTER DATABASE tempdb 
MODIFY FILE (NAME = temp3, SIZE = 64MB);
GO

ALTER DATABASE tempdb 
MODIFY FILE (NAME = temp4, SIZE = 64MB);
GO

ALTER DATABASE tempdb 
MODIFY FILE (NAME = temp5, SIZE = 64MB);
GO

ALTER DATABASE tempdb 
MODIFY FILE (NAME = temp6, SIZE = 64MB);
GO

ALTER DATABASE tempdb 
MODIFY FILE (NAME = temp7, SIZE = 64MB);
GO

ALTER DATABASE tempdb 
MODIFY FILE (NAME = temp8, SIZE = 64MB);
GO

-- Alter tempdb log file to set size to 100MB
ALTER DATABASE tempdb 
MODIFY FILE (NAME = templog, SIZE = 1000MB);
GO