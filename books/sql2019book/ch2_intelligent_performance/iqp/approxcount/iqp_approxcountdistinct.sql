-- Step 1: Clear the cache, set dbcompat to 130 just to prove it works, and warm the cache
USE WideWorldImportersDW
GO
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE
GO
ALTER DATABASE WideWorldImportersDW SET COMPATIBILITY_LEVEL = 130
GO
SELECT COUNT(*) FROM Fact.OrderHistoryExtended
GO

-- Step 2: Use COUNT and DISTINCT first
SELECT COUNT(DISTINCT [WWI Order ID])
FROM [Fact].[OrderHistoryExtended]
GO

-- Step 3: Use the new APPROX_COUNT_DISTINCT function to compare values and performance
-- We should be no more than 2% off the actual distinct value (97% probability)
SELECT APPROX_COUNT_DISTINCT([WWI Order ID])
FROM [Fact].[OrderHistoryExtended]
GO

-- Step 4: Restore database compatibility level
ALTER DATABASE WideWorldImportersDW SET COMPATIBILITY_LEVEL = 150
GO