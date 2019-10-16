-- Step 1: Make sure this database is in compatibility level 150 and clear procedure cache for this database. Also bring the table into cache to compare warm cache queries
ALTER DATABASE [wideworldimportersdw] SET COMPATIBILITY_LEVEL = 150
GO
USE [wideworldimportersdw]
GO
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE
GO
SELECT COUNT(*) FROM [Fact].[OrderHistory]
GO

-- Step 2: Simulate statistics out of date
UPDATE STATISTICS Fact.OrderHistory 
WITH ROWCOUNT = 5000000000
GO

-- Step 3: Turn off memory grant for row and batch feedback
ALTER DATABASE SCOPED CONFIGURATION SET ROW_MODE_MEMORY_GRANT_FEEDBACK = OFF
GO
ALTER DATABASE SCOPED CONFIGURATION SET BATCH_MODE_MEMORY_GRANT_FEEDBACK = OFF
GO

-- Step 4: Run a query to get order and stock item data
-- Check the Memory Grant for the overall query
-- DO NOT select the comments here to run the query!
SELECT fo.[Order Key], fo.Description, si.[Lead Time Days]
FROM  Fact.OrderHistory AS fo
INNER JOIN Dimension.[Stock Item] AS si 
ON fo.[Stock Item Key] = si.[Stock Item Key]
WHERE fo.[Lineage Key] = 9
AND si.[Lead Time Days] > 19
ORDER BY fo.[Order Key], fo.Description, si.[Lead Time Days]
OPTION (MAXDOP 1)
GO

-- Step 5: Turn on memory grant feedback
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE
GO
ALTER DATABASE SCOPED CONFIGURATION SET ROW_MODE_MEMORY_GRANT_FEEDBACK = ON
GO
ALTER DATABASE SCOPED CONFIGURATION SET BATCH_MODE_MEMORY_GRANT_FEEDBACK = ON
GO

-- Step 6: Try the query again and check the actual grant
-- Check the Memory Grant for the overall query
-- DO NOT select the comments here to run the query!
SELECT fo.[Order Key], fo.Description, si.[Lead Time Days]
FROM  Fact.OrderHistory AS fo
INNER JOIN Dimension.[Stock Item] AS si 
ON fo.[Stock Item Key] = si.[Stock Item Key]
WHERE fo.[Lineage Key] = 9
AND si.[Lead Time Days] > 19
ORDER BY fo.[Order Key], fo.Description, si.[Lead Time Days]
OPTION (MAXDOP 1)
GO

-- Step 7: Run the query again
-- Check the Memory Grant for the overall query
-- DO NOT select the comments here to run the query!
SELECT fo.[Order Key], fo.Description, si.[Lead Time Days]
FROM  Fact.OrderHistory AS fo
INNER JOIN Dimension.[Stock Item] AS si 
ON fo.[Stock Item Key] = si.[Stock Item Key]
WHERE fo.[Lineage Key] = 9
AND si.[Lead Time Days] > 19
ORDER BY fo.[Order Key], fo.Description, si.[Lead Time Days]
OPTION (MAXDOP 1)
GO

-- Step 8: Restore table and clustered index back to its original state
UPDATE STATISTICS Fact.OrderHistory 
WITH ROWCOUNT = 3702592;
GO
ALTER TABLE [Fact].[OrderHistory] DROP CONSTRAINT [PK_Fact_OrderHistory]
GO
ALTER TABLE [Fact].[OrderHistory] ADD  CONSTRAINT [PK_Fact_OrderHistory] PRIMARY KEY NONCLUSTERED 
(
	[Order Key] ASC,
	[Order Date Key] ASC
)
GO