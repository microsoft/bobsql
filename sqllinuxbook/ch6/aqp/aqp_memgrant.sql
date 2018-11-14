---------------------------------------------------
-- *** Batch-Mode Memory Grant Feedback Demo *** --
---------------------------------------------------
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO

ALTER DATABASE [WideWorldImportersDW] SET COMPATIBILITY_LEVEL = 140
go

USE [WideWorldImportersDW]
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
go