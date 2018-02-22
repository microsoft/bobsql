USE [WideWorldImportersDW]
GO

/****** Object:  UserDefinedFunction [Fact].[WhatIfOutlierEventQuantity]    Script Date: 5/4/2017 4:02:36 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE FUNCTION [Fact].[WhatIfOutlierEventQuantity](@event VARCHAR(15), @beginOrderDateKey DATE, @endOrderDateKey DATE)
RETURNS @OutlierEventQuantity TABLE (
	[Order Key] [bigint],
	[City Key] [int] NOT NULL,
	[Customer Key] [int] NOT NULL,
	[Stock Item Key] [int] NOT NULL,
	[Order Date Key] [date] NOT NULL,
	[Picked Date Key] [date] NULL,
	[Salesperson Key] [int] NOT NULL,
	[Picker Key] [int] NULL,
	[OutlierEventQuantity] [int] NOT NULL)
AS 
BEGIN

-- Valid @event values
	-- 'Mild Recession'
	-- 'Hurricane - South Atlantic'
	-- 'Hurricane - East South Central'
	-- 'Hurricane - West South Central'
	IF @event = 'Mild Recession'
    INSERT  @OutlierEventQuantity
	SELECT [o].[Order Key], [o].[City Key], [o].[Customer Key],
           [o].[Stock Item Key], [o].[Order Date Key], [o].[Picked Date Key],
           [o].[Salesperson Key], [o].[Picker Key], 
           CASE
			WHEN [o].[Quantity] > 2 THEN [o].[Quantity] * .5
			ELSE [o].[Quantity]
		   END 
	FROM [Fact].[Order] AS [o]
	INNER JOIN [Dimension].[City] AS [c]
		ON [c].[City Key] = [o].[City Key]

	IF @event = 'Hurricane - South Atlantic'
    INSERT  @OutlierEventQuantity
	SELECT [o].[Order Key], [o].[City Key], [o].[Customer Key],
           [o].[Stock Item Key], [o].[Order Date Key], [o].[Picked Date Key],
           [o].[Salesperson Key], [o].[Picker Key], 
           CASE
			WHEN [o].[Quantity] > 10 THEN [o].[Quantity] * .5
			ELSE [o].[Quantity]
		   END 
	FROM [Fact].[Order] AS [o]
	INNER JOIN [Dimension].[City] AS [c]
		ON [c].[City Key] = [o].[City Key]
	WHERE [c].[State Province] IN
	('Florida', 'Georgia', 'Maryland', 'North Carolina',
	'South Carolina', 'Virginia', 'West Virginia',
	'Delaware')
	AND [o].[Order Date Key] BETWEEN @beginOrderDateKey AND @endOrderDateKey

	IF @event = 'Hurricane - East South Central'
    INSERT  @OutlierEventQuantity
	SELECT [o].[Order Key], [o].[City Key], [o].[Customer Key],
           [o].[Stock Item Key], [o].[Order Date Key], [o].[Picked Date Key],
           [o].[Salesperson Key], [o].[Picker Key], 
           CASE
			WHEN [o].[Quantity] > 50 THEN [o].[Quantity] * .5
			ELSE [o].[Quantity]
		   END
	FROM [Fact].[Order] AS [o]
	INNER JOIN [Dimension].[City] AS [c]
		ON [c].[City Key] = [o].[City Key]
	INNER JOIN [Dimension].[Stock Item] AS [si]
	ON [si].[Stock Item Key] = [o].[Stock Item Key]
	WHERE [c].[State Province] IN
	('Alabama', 'Kentucky', 'Mississippi', 'Tennessee')
	AND [si].[Buying Package] = 'Carton'
	AND [o].[Order Date Key] BETWEEN @beginOrderDateKey AND @endOrderDateKey

	IF @event = 'Hurricane - West South Central'
    INSERT  @OutlierEventQuantity
	SELECT [o].[Order Key], [o].[City Key], [o].[Customer Key],
           [o].[Stock Item Key], [o].[Order Date Key], [o].[Picked Date Key],
           [o].[Salesperson Key], [o].[Picker Key], 
           CASE
		    WHEN [cu].[Customer] = 'Unknown' THEN 0
			WHEN [cu].[Customer] <> 'Unknown' AND
			 [o].[Quantity] > 10 THEN [o].[Quantity] * .5
			ELSE [o].[Quantity]
		   END
	FROM [Fact].[Order] AS [o]
	INNER JOIN [Dimension].[City] AS [c]
		ON [c].[City Key] = [o].[City Key]
	INNER JOIN [Dimension].[Customer] AS [cu]
	ON [cu].[Customer Key] = [o].[Customer Key]
	WHERE [c].[State Province] IN
	('Arkansas', 'Louisiana', 'Oklahoma', 'Texas')
	AND [o].[Order Date Key] BETWEEN @beginOrderDateKey AND @endOrderDateKey

    RETURN
END
GO


