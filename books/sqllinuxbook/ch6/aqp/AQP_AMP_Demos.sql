USE [master]
GO

ALTER DATABASE [WideWorldImportersDW] SET COMPATIBILITY_LEVEL = 130;
GO

ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO

----------------------------------------
-- *** Interleaved Execution Demo *** --
----------------------------------------
USE [WideWorldImportersDW];
GO

-- Our "before" state 
-- Include Actual Execution Plan
SELECT  [fo].[Order Key], [fo].[Description], [fo].[Package],
		[fo].[Quantity], [foo].[OutlierEventQuantity]
FROM    [Fact].[Order] AS [fo]
INNER JOIN [Fact].[WhatIfOutlierEventQuantity]('Mild Recession',
                            '1-01-2013',
                            '10-15-2014') AS [foo] ON [fo].[Order Key] = [foo].[Order Key]
                            AND [fo].[City Key] = [foo].[City Key]
                            AND [fo].[Customer Key] = [foo].[Customer Key]
                            AND [fo].[Stock Item Key] = [foo].[Stock Item Key]
                            AND [fo].[Order Date Key] = [foo].[Order Date Key]
                            AND [fo].[Picked Date Key] = [foo].[Picked Date Key]
                            AND [fo].[Salesperson Key] = [foo].[Salesperson Key]
                            AND [fo].[Picker Key] = [foo].[Picker Key]
INNER JOIN [Dimension].[Stock Item] AS [si] 
	ON [fo].[Stock Item Key] = [si].[Stock Item Key]
WHERE   [si].[Lead Time Days] > 0
		AND [fo].[Quantity] > 50;

-- Plan observations:
--		Notice the TVF estimated number of rows
--		Notice the spills 

USE [master];
GO

ALTER DATABASE [WideWorldImportersDW] SET COMPATIBILITY_LEVEL = 140;
GO

ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO

USE [WideWorldImportersDW];
GO
-- TODO (open separate window to compare plan shapes)
-- Our "after" state (with Interleaved execution) 
-- Include Actual Execution Plan
SELECT  [fo].[Order Key], [fo].[Description], [fo].[Package],
		[fo].[Quantity], [foo].[OutlierEventQuantity]
FROM    [Fact].[Order] AS [fo]
INNER JOIN [Fact].[WhatIfOutlierEventQuantity]('Mild Recession',
                            '1-01-2013',
                            '10-15-2014') AS [foo] ON [fo].[Order Key] = [foo].[Order Key]
                            AND [fo].[City Key] = [foo].[City Key]
                            AND [fo].[Customer Key] = [foo].[Customer Key]
                            AND [fo].[Stock Item Key] = [foo].[Stock Item Key]
                            AND [fo].[Order Date Key] = [foo].[Order Date Key]
                            AND [fo].[Picked Date Key] = [foo].[Picked Date Key]
                            AND [fo].[Salesperson Key] = [foo].[Salesperson Key]
                            AND [fo].[Picker Key] = [foo].[Picker Key]
INNER JOIN [Dimension].[Stock Item] AS [si] 
	ON [fo].[Stock Item Key] = [si].[Stock Item Key]
WHERE   [si].[Lead Time Days] > 0
		AND [fo].[Quantity] > 50;

-- Plan observations:
--		Notice the TVF estimated number of rows (did it change?)
--		Any spills?

---------------------------------------------------
-- *** Batch-Mode Memory Grant Feedback Demo *** --
---------------------------------------------------
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO

-- Intentionally forcing a row underestimate
DROP PROCEDURE IF EXISTS [FactOrderByLineageKey];
GO
CREATE PROCEDURE [FactOrderByLineageKey]
	@LineageKey INT 
AS
SELECT   
	[fo].[Order Key], [fo].[Description] 
FROM    [Fact].[Order] AS [fo]
INNER HASH JOIN [Dimension].[Stock Item] AS [si] 
	ON [fo].[Stock Item Key] = [si].[Stock Item Key]
WHERE   [fo].[Lineage Key] = @LineageKey
	AND [si].[Lead Time Days] > 0
ORDER BY [fo].[Stock Item Key], [fo].[Order Date Key] DESC
OPTION (MAXDOP 1);
GO

-- Compiled and executed using a lineage key that doesn't have rows
EXEC [FactOrderByLineageKey] 8;

-- Execute this query a few times - each time looking at 
-- the plan to see impact on spills, memory grant size, and run time
EXEC [FactOrderByLineageKey] 9;

-------------------------------------------
-- *** Batch-Mode Adaptive Join Demo *** --
-------------------------------------------
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO

-- Show live query stats
SELECT  [fo].[Order Key], [si].[Lead Time Days], [fo].[Quantity]
FROM    [Fact].[Order] AS [fo]
INNER JOIN [Dimension].[Stock Item] AS [si] 
	ON [fo].[Stock Item Key] = [si].[Stock Item Key]
WHERE   [fo].[Quantity] = 360;

-- Inserting quantity row that doesn't exist in the table yet
DELETE [Fact].[Order] 
WHERE Quantity = 361;

INSERT [Fact].[Order] 
([City Key], [Customer Key], [Stock Item Key], [Order Date Key], [Picked Date Key], [Salesperson Key], [Picker Key], [WWI Order ID], [WWI Backorder ID], Description, Package, Quantity, [Unit Price], [Tax Rate], [Total Excluding Tax], [Tax Amount], [Total Including Tax], [Lineage Key])
SELECT TOP 5 [City Key], [Customer Key], [Stock Item Key],
 [Order Date Key], [Picked Date Key], [Salesperson Key], 
 [Picker Key], [WWI Order ID], [WWI Backorder ID], 
 Description, Package, 361, [Unit Price], [Tax Rate], 
 [Total Excluding Tax], [Tax Amount], [Total Including Tax], 
 [Lineage Key]
FROM [Fact].[Order];

SELECT  [fo].[Order Key], [si].[Lead Time Days], [fo].[Quantity]
FROM    [Fact].[Order] AS [fo]
INNER JOIN [Dimension].[Stock Item] AS [si] 
	ON [fo].[Stock Item Key] = [si].[Stock Item Key]
WHERE   [fo].[Quantity] = 361;

