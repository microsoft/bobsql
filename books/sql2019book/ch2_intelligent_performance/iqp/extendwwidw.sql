-- Create new romode tables that large based on WideWorldImportersDW
-- Credits to Joe Sack from Microsoft for this script
-- This assumes you have restored the WideWorldImportersDW full backup from XXXXXX

USE WideWorldImportersDW
GO

-- Build a new rowmode table called OrderHistory based off of Orders
--
DROP TABLE IF EXISTS Fact.OrderHistory
GO

SELECT 'Buliding OrderHistory from Orders...'
GO
SELECT [Order Key], [City Key], [Customer Key], [Stock Item Key], [Order Date Key], [Picked Date Key], [Salesperson Key], [Picker Key], [WWI Order ID], [WWI Backorder ID], Description, Package, Quantity, [Unit Price], [Tax Rate], [Total Excluding Tax], [Tax Amount], [Total Including Tax], [Lineage Key]
INTO Fact.OrderHistory
FROM Fact.[Order]
GO

ALTER TABLE Fact.OrderHistory
ADD CONSTRAINT PK_Fact_OrderHistory PRIMARY KEY NONCLUSTERED([Order Key] ASC, [Order Date Key] ASC)WITH(DATA_COMPRESSION=PAGE);
GO

CREATE INDEX IX_Stock_Item_Key
ON Fact.OrderHistory([Stock Item Key])
INCLUDE(Quantity)
WITH(DATA_COMPRESSION=PAGE)
GO

CREATE INDEX IX_OrderHistory_Quantity
ON Fact.OrderHistory([Quantity])
INCLUDE([Order Key])
WITH(DATA_COMPRESSION=PAGE)
GO

-- Table should have 231,412 rows
SELECT 'Number of rows in Fact.OrderHistory = ', COUNT(*) FROM Fact.OrderHistory
GO

SELECT 'Increasing number of rows for OrderHistory...'
GO
-- Make the table bigger
INSERT Fact.OrderHistory([City Key], [Customer Key], [Stock Item Key], [Order Date Key], [Picked Date Key], [Salesperson Key], [Picker Key], [WWI Order ID], [WWI Backorder ID], Description, Package, Quantity, [Unit Price], [Tax Rate], [Total Excluding Tax], [Tax Amount], [Total Including Tax], [Lineage Key])
SELECT [City Key], [Customer Key], [Stock Item Key], [Order Date Key], [Picked Date Key], [Salesperson Key], [Picker Key], [WWI Order ID], [WWI Backorder ID], Description, Package, Quantity, [Unit Price], [Tax Rate], [Total Excluding Tax], [Tax Amount], [Total Including Tax], [Lineage Key]
FROM Fact.OrderHistory
GO 4

-- Table should have 3,702,592 rows
SELECT 'Number of rows in Fact.OrderHistory = ', COUNT(*) FROM Fact.OrderHistory
GO

SELECT 'Building OrderHistoryExtended from OrderHistory...'
GO
-- Bulid an even bigger rowmode table based on OrderHistory
DROP TABLE IF EXISTS Fact.OrderHistoryExtended
GO
SELECT [Order Key], [City Key], [Customer Key], [Stock Item Key], [Order Date Key], [Picked Date Key], [Salesperson Key], [Picker Key], [WWI Order ID], [WWI Backorder ID], Description, Package, Quantity, [Unit Price], [Tax Rate], [Total Excluding Tax], [Tax Amount], [Total Including Tax], [Lineage Key]
INTO Fact.OrderHistoryExtended
FROM Fact.[OrderHistory]
GO

ALTER TABLE Fact.OrderHistoryExtended
ADD CONSTRAINT PK_Fact_OrderHistoryExtended PRIMARY KEY NONCLUSTERED([Order Key] ASC, [Order Date Key] ASC)
WITH(DATA_COMPRESSION=PAGE)
GO

CREATE INDEX IX_Stock_Item_Key
ON Fact.OrderHistoryExtended([Stock Item Key])
INCLUDE(Quantity);
GO

-- Table should have 3,702,592 rows
SELECT 'Number of rows in Fact.OrderHistoryExtended = ', COUNT(*) FROM Fact.OrderHistoryExtended
GO

SELECT 'Increasing number of rows for OrderHistoryExtended...'
GO

-- Make the table bigger
INSERT Fact.OrderHistoryExtended([City Key], [Customer Key], [Stock Item Key], [Order Date Key], [Picked Date Key], [Salesperson Key], [Picker Key], [WWI Order ID], [WWI Backorder ID], Description, Package, Quantity, [Unit Price], [Tax Rate], [Total Excluding Tax], [Tax Amount], [Total Including Tax], [Lineage Key])
SELECT [City Key], [Customer Key], [Stock Item Key], [Order Date Key], [Picked Date Key], [Salesperson Key], [Picker Key], [WWI Order ID], [WWI Backorder ID], Description, Package, Quantity, [Unit Price], [Tax Rate], [Total Excluding Tax], [Tax Amount], [Total Including Tax], [Lineage Key]
FROM Fact.OrderHistoryExtended;
GO 3

-- Table should have 29,620,736 rows
SELECT 'Number of rows in Fact.OrderHistoryExtended = ', COUNT(*) FROM Fact.OrderHistoryExtended
GO

UPDATE Fact.OrderHistoryExtended
SET [WWI Order ID] = [Order Key];
GO