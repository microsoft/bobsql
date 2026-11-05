-- Query archive table
--
USE SalesDB;
GO
SELECT * FROM SalesArchiveSept2022;
GO
-- Combine existing sales with Archive
--
SELECT * FROM Sales
UNION
SELECT * FROM SalesArchiveSept2022
ORDER BY sales_dt;
GO

-- Optionally truncate SalesArchive
--
TRUNCATE TABLE SalesArchive;
GO