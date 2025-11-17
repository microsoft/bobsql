USE master;
GO

-- Alter tempdb data files to set size to default of 8MB per file for 8 files and 8MB log file
ALTER DATABASE tempdb 
MODIFY FILE (NAME = tempdev, SIZE = 8MB);
GO

ALTER DATABASE tempdb 
MODIFY FILE (NAME = temp2, SIZE = 8MB);
GO

ALTER DATABASE tempdb 
MODIFY FILE (NAME = temp3, SIZE = 8MB);
GO

ALTER DATABASE tempdb 
MODIFY FILE (NAME = temp4, SIZE = 8MB);
GO

ALTER DATABASE tempdb 
MODIFY FILE (NAME = temp5, SIZE = 8MB);
GO

ALTER DATABASE tempdb 
MODIFY FILE (NAME = temp6, SIZE = 8MB);
GO

ALTER DATABASE tempdb 
MODIFY FILE (NAME = temp7, SIZE = 8MB);
GO

ALTER DATABASE tempdb 
MODIFY FILE (NAME = temp8, SIZE = 8MB);
GO

-- Alter tempdb log file to set size to 100MB
ALTER DATABASE tempdb 
MODIFY FILE (NAME = templog, SIZE = 8MB);
GO