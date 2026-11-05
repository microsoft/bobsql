-- Step 1: Create a stored procedure using a table variable to show the top 10 past orders by price
USE WideWorldImportersDW
GO
CREATE OR ALTER PROCEDURE Fact.OrderPrices
AS
BEGIN
DECLARE @Order TABLE 
	([Order Key] BIGINT NOT NULL,
	 [Quantity] INT NOT NULL
	)

INSERT @Order
SELECT [Order Key], [Quantity]
FROM [Fact].[OrderHistory]

-- Look at estimated rows, speed, join algorithm
SELECT top 10 oh.[Order Key], oh.[Order Date Key],oh.[Unit Price], o.Quantity
FROM Fact.OrderHistoryExtended AS oh
INNER JOIN @Order AS o
ON o.[Order Key] = oh.[Order Key]
WHERE oh.[Unit Price] > 0.10
ORDER BY oh.[Unit Price] DESC
END
GO

-- Step 2: Change WideWorldImportersDW to dbcompat 130 to see legacy behavior
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE
GO
ALTER DATABASE WideWorldImportersDW SET COMPATIBILITY_LEVEL = 130
GO
SELECT COUNT(*) FROM Fact.OrderHistoryExtended
GO

-- Step 3: Run the Fact.OrderPrices procedure 3 times
EXEC Fact.OrderPrices
GO 3

-- Step 4: Change WideWorldImportersDW to dbcompat 150 to see legacy behavior
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE
GO
ALTER DATABASE WideWorldImportersDW SET COMPATIBILITY_LEVEL = 150
GO

-- Step 5: Is it any faster?
EXEC Fact.OrderPrices
GO 3