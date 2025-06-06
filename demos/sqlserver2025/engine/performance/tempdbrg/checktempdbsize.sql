-- Created by Copilot in SSMS - review carefully before executing

USE tempdb;
GO

-- Query to track space usage for tempdb
SELECT 
    name AS FileName,
    size / 128.0 AS CurrentSizeMB,
    size / 128.0 - CAST(FILEPROPERTY(name, 'SpaceUsed') AS INT) / 128.0 AS FreeSpaceMB,
    CAST(FILEPROPERTY(name, 'SpaceUsed') AS INT) / 128.0 AS UsedSpaceMB,
    physical_name AS PhysicalFileName
FROM 
    sys.database_files;