-- Step 1: Create a new function to get a customer category based on their order spend
USE WideWorldImportersDW
GO

CREATE OR ALTER FUNCTION [Dimension].[customer_category](@CustomerKey INT) 
RETURNS CHAR(10) AS
BEGIN
DECLARE @total_amount DECIMAL(18,2);
DECLARE @category CHAR(10);

SELECT @total_amount = 	SUM([Total Including Tax]) 
FROM [Fact].[OrderHistory]
WHERE [Customer Key] = @CustomerKey

IF @total_amount <= 3000000
 SET @category = 'REGULAR'
ELSE IF @total_amount < 4500000
 SET @category = 'GOLD'
ELSE 
 SET @category = 'PLATINUM'

RETURN @category
END
GO

-- Step 2: Set the database to db compat 150, clear the procedure cache from previous executions, and make the comparison fair by warming the cache
ALTER DATABASE WideWorldImportersDW 
SET COMPATIBILITY_LEVEL = 150
GO
ALTER DATABASE SCOPED CONFIGURATION 
CLEAR PROCEDURE_CACHE
GO
SELECT COUNT(*) FROM [Fact].[OrderHistory]
GO

-- Step 3: Run the query but disable the use of scalar inlining using a query hint
SELECT [Customer Key], [Customer], [Dimension].[customer_category]([Customer Key]) AS [Discount Price]
FROM [Dimension].[Customer]
ORDER BY [Customer Key]
OPTION (USE HINT('DISABLE_TSQL_SCALAR_UDF_INLINING'))
GO

-- Step 4: Run it again but don't use the hint
SELECT [Customer Key], [Customer], [Dimension].[customer_category]([Customer Key]) AS [Discount Price]
FROM [Dimension].[Customer]
ORDER BY [Customer Key]
GO
