USE WideWorldImporters
GO

-- Build a new rowmode table called OrderHistory based off of Orders
DROP TABLE IF EXISTS Sales.InvoiceLinesExtended
GO

SELECT 'Building InvoiceLinesExtended from InvoiceLines...'
GO

CREATE TABLE [Sales].[InvoiceLinesExtended](
	[InvoiceLineID] [int] IDENTITY NOT NULL,
	[InvoiceID] [int] NOT NULL,
	[StockItemID] [int] NOT NULL,
	[Description] [nvarchar](100) NOT NULL,
	[PackageTypeID] [int] NOT NULL,
	[Quantity] [int] NOT NULL,
	[UnitPrice] [decimal](18, 2) NULL,
	[TaxRate] [decimal](18, 3) NOT NULL,
	[TaxAmount] [decimal](18, 2) NOT NULL,
	[LineProfit] [decimal](18, 2) NOT NULL,
	[ExtendedPrice] [decimal](18, 2) NOT NULL,
	[LastEditedBy] [int] NOT NULL,
	[LastEditedWhen] [datetime2](7) NOT NULL,
 CONSTRAINT [PK_Sales_InvoiceLinesExtended] PRIMARY KEY CLUSTERED 
(
	[InvoiceLineID] ASC
))
GO

CREATE INDEX IX_StockItemID
ON Sales.InvoiceLinesExtended([StockItemID])
WITH(DATA_COMPRESSION=PAGE)
GO

INSERT Sales.InvoiceLinesExtended(InvoiceID, StockItemID, Description, PackageTypeID, Quantity, UnitPrice, TaxRate, TaxAmount, LineProfit, ExtendedPrice, LastEditedBy, LastEditedWhen)
SELECT InvoiceID, StockItemID, Description, PackageTypeID, Quantity, UnitPrice, TaxRate, TaxAmount, LineProfit, ExtendedPrice, LastEditedBy, LastEditedWhen
FROM Sales.InvoiceLines
GO

-- Table should have 228,265 rows
SELECT 'Number of rows in Sales.InvoiceLinesExtended = ', COUNT(*) FROM Sales.InvoiceLinesExtended
GO

SELECT 'Increasing number of rows for InvoiceLinesExtended...'
GO
-- Make the table bigger
INSERT Sales.InvoiceLinesExtended(InvoiceID, StockItemID, Description, PackageTypeID, Quantity, UnitPrice, TaxRate, TaxAmount, LineProfit, ExtendedPrice, LastEditedBy, LastEditedWhen)
SELECT InvoiceID, StockItemID, Description, PackageTypeID, Quantity, UnitPrice, TaxRate, TaxAmount, LineProfit, ExtendedPrice, LastEditedBy, LastEditedWhen
FROM Sales.InvoiceLinesExtended
GO 4

-- Table should have 3,652,240 rows
SELECT 'Number of rows in Sales.InvoiceLinesExtended = ', COUNT(*) FROM Sales.InvoiceLinesExtended
GO

SELECT COUNT(DISTINCT(StockItemID)) FROM Sales.InvoiceLinesExtended